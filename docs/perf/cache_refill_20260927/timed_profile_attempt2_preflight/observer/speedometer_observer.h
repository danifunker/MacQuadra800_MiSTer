#ifndef SPEEDOMETER_OBSERVER_H
#define SPEEDOMETER_OBSERVER_H
#include <array>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <ostream>
#include <string>

// Host-side observer only. Input memory transfers are successful, CE-qualified
// core-side acknowledgements, sampled BEFORE the edge. Addresses are logical;
// data has already traversed the real MMU/cache. Never dereferences guest RAM.
namespace speedometer {
struct Context {
    std::array<uint32_t,7> mmu{}; // TC,URP,SRP,ITT0,ITT1,DTT0,DTT1
    bool operator==(const Context& b) const { return mmu==b.mmu; }
};
struct Registers {
    std::array<uint32_t,8> d{},a{};
    uint16_t sr=0;
    bool pending=false,aux=false;
    uint8_t pending_reg=0;
    uint32_t pending_data=0;
};
struct Bus {
    uint64_t cycle=0;
    uint32_t pc=0,addr=0,data=0;
    uint8_t bytes=0,fc=0;
    bool request=false,ack=false,error=false,ce=true,instruction=false,write=false;
};
// Simulation-only FPU timer/callback boundaries. `cycle` is a dispatch
// boundary, not the instant at which the guest timer trap samples its clock.
struct FpuEvent {
    enum Kind { Identify, TimerStart, TimerStop, TimerRawStop,
                CallbackStart, CallbackStop, Abort, Unmatched } kind;
    uint64_t cycle=0;
    unsigned site=0;           // resource CODE3 sites 0/1/2; no score label inferred
    bool microseconds=false;   // false means the guest's fallback timer path
    uint64_t raw=0;            // A0:D0 at a Microseconds return, when available
    const char* reason="";
};
inline void apply_pending(Registers& r,bool we,uint8_t reg,uint32_t data,
                          bool aux,uint8_t aux_sel,uint32_t aux_data) {
    r.pending=we;r.pending_reg=reg;r.pending_data=data;r.aux=aux;
    if(we) {if(reg<8)r.d[reg]=data;else r.a[reg-8]=data;}
    const unsigned sp=!(r.sr&0x2000)?0:((r.sr&0x1000)?2:1);
    if(aux && aux_sel==sp)r.a[7]=aux_data;
}

class Observer {
    struct Byte { uint32_t addr=0; uint8_t fc=0,value=0; bool valid=false; };
    // Direct-mapped bounded cache; collisions only prevent identification.
    std::array<Byte,4096> code_{};
    Context context_{};
    bool context_valid_=false,identified_=false,reset_=false;
    uint32_t base_=0,a5_=0,a6_=0;
    uint8_t code_fc_=0;
    unsigned test_=0;
    uint64_t limit_,records_=0,identities_=0,starts_=0,stops_=0,contexts_=0;
    unsigned prefix_=0,prefix_test_=0;
    uint32_t prefix_pc_=0,prefix_a5_=0;
    std::ostream& out_;
    bool have_start_=false,have_stop_=false,have_aggregate_=false,micro_start_=false,window_=false;
    uint64_t start_=0,stop_=0,start_cycle_=0,stop_cycle_=0;
    uint32_t before_d4_=0,elapsed_=0;
    uint8_t elapsed_mask_=0;
    std::function<void(const FpuEvent&)> fpu_sink_;
    unsigned fpu_prefix_=0, fpu_prefix_site_=0, fpu_site_=0;
    uint32_t fpu_prefix_pc_=0, fpu_prefix_a5_=0, fpu_base_=0;
    uint8_t fpu_fc_=0;
    bool fpu_identified_=false, fpu_timer_=false, fpu_callback_=false;
    bool fpu_raw_pending_=false, fpu_callback_complete_=false;
    bool fpu_microseconds_=false;
    uint64_t fpu_last_cycle_=0, fpu_starts_=0, fpu_stops_=0;
    uint64_t fpu_callbacks_=0, fpu_returns_=0, fpu_aborts_=0, fpu_unmatched_=0;
    uint64_t fpu_prefix_aborts_=0;
    uint64_t diag_rows_=0,diag_priority_rows_=0,diag_dropped_=0,dispatches_=0,known_dispatches_=0,ir_mismatch_=0;
    uint64_t request_samples_=0,ack_samples_=0,instruction_acks_=0,data_acks_=0,fetched_bytes_=0,error_acks_=0;
    uint64_t signature_failures_=0,secondary_skipped_=0,primary_mismatch_skipped_=0;
    std::array<uint64_t,6> prefix_transitions_{};
    std::array<uint64_t,6> invalidations_{};
    std::array<std::array<uint64_t,6>,6> invalidation_phases_{};
    void diagnostic(uint64_t cycle,const char* kind,uint32_t pc,const char* reason="",unsigned site=3) {
        const bool priority=fpu_prefix_>=4 || std::string(kind)=="SIGNATURE_FAIL" ||
            std::string(kind)=="IDENTIFY" || std::string(kind).find("FPU_")==0 ||
            (std::string(kind)=="INVALIDATE" && fpu_identified_);
        const bool allowed=priority ? diag_priority_rows_++<2048 : diag_rows_++<2048;
        if(allowed) {
            out_<<"LIVE cycle="<<cycle<<" kind="<<kind<<" phase="<<fpu_prefix_
                <<" site="<<(site<3?site:(fpu_identified_?fpu_site_:fpu_prefix_site_))<<" pc="<<std::hex<<pc<<std::dec<<" reason="<<reason<<'\n';
            out_.flush();
        } else ++diag_dropped_;
    }
    void prefix_change(uint64_t cycle,uint32_t pc,unsigned before) {
        if(before!=fpu_prefix_) {++prefix_transitions_[fpu_prefix_];diagnostic(cycle,"PREFIX",pc);}
    }

    static constexpr uint32_t fpu_prefix_at_[3]={0x4f4a,0x50bc,0x527a};
    static constexpr uint32_t fpu_prefix_return_[3]={0x4f5c,0x50ce,0x528c};
    static constexpr uint32_t fpu_micro_start_[3]={0x4f68,0x50f2,0x52b0};
    static constexpr uint32_t fpu_fallback_start_[3]={0x4f7c,0x5106,0x52c4};
    static constexpr uint32_t fpu_call_[3]={0x4f80,0x510a,0x52c8};
    static constexpr uint32_t fpu_return_[3]={0x4f82,0x510c,0x52ca};
    static constexpr uint32_t fpu_micro_stop_[3]={0x4f8e,0x5118,0x52d6};
    static constexpr uint32_t fpu_micro_stop_return_[3]={0x4f90,0x511a,0x52d8};
    static constexpr uint32_t fpu_fallback_stop_[3]={0x4fa8,0x5132,0x52f0};
    static constexpr uint16_t fpu_selector_[3]={0x24,0x42,0x56};
    static constexpr uint16_t fpu_return_word_[3]={0x4a2d,0x7800,0x7800};
    static constexpr uint16_t fpu_timer_return_word_[3]={0x225f,0x225f,0x225f};
    void fpu_event(FpuEvent::Kind kind,uint64_t cycle,unsigned site,bool micro=false,
                   uint64_t raw=0,const char* reason="") {
        FpuEvent e{kind,cycle,site,micro,raw,reason};
        if(fpu_sink_)fpu_sink_(e);
        static const char* names[]={"FPU_Identify","FPU_TimerStart","FPU_TimerStop","FPU_TimerRawStop",
            "FPU_CallbackStart","FPU_CallbackStop","FPU_Abort","FPU_Unmatched"};
        diagnostic(cycle,names[kind],0,reason,site);
    }
    void fpu_abort(uint64_t cycle,const char* reason) {
        if(fpu_timer_||fpu_callback_||fpu_raw_pending_) {
            fpu_event(FpuEvent::Abort,cycle,fpu_site_,fpu_microseconds_,0,reason);
            ++fpu_aborts_;
        }
        fpu_timer_=fpu_callback_=fpu_raw_pending_=fpu_callback_complete_=false;
    }
    void fpu_drop_identity(uint64_t cycle,const char* reason) {
        // A cache/MMU invalidation during the helper call can clear the
        // executed prefix before its post-JSR signature is visible. Count
        // that separately from an identified timer-span abort.
        const unsigned bucket=std::string(reason)=="MMU_REGISTERS"?0:std::string(reason)=="PFLUSH_OR_CINV"?1:
            std::string(reason)=="RESET"?2:std::string(reason)=="CODE_WRITE"?3:std::string(reason)=="CODE3_RELOCATED"?4:5;
        ++invalidations_[bucket];++invalidation_phases_[bucket][fpu_prefix_];
        if(fpu_prefix_||fpu_identified_||fpu_timer_||fpu_callback_||fpu_raw_pending_)
            diagnostic(cycle,"INVALIDATE",fpu_prefix_pc_,reason);
        if(fpu_prefix_)++fpu_prefix_aborts_;
        fpu_abort(cycle,reason);fpu_identified_=false;fpu_prefix_=0;
    }
    bool fpu_signature(uint32_t pc,uint8_t fc,unsigned site,uint32_t* failed_pc=nullptr,const char** reason=nullptr) const {
        const uint8_t sig[]={0x3b,0x7c,0,4,0xbe,0xaa,0x3b,0x7c,
                             uint8_t(fpu_selector_[site]>>8),
                             uint8_t(fpu_selector_[site]),0xbe,0xac,
                             0x4e,0xb9,0,0,0x4d,0x36,
                             uint8_t(fpu_return_word_[site]>>8),
                             uint8_t(fpu_return_word_[site])};
        for(unsigned i=0;i<sizeof(sig);i++) {
            if(i>=14 && i<18)continue; // loader relocates JSR's absolute target
            uint8_t v;
            const bool present=get(pc-18+i,fc,v);
            if(!present||v!=sig[i]) {
                if(failed_pc)*failed_pc=pc-18+i;
                if(reason)*reason=present?"SIGNATURE_BYTE_MISMATCH":"MISSING_SIGNATURE_BYTE";
                return false;
            }
        }
        return true;
    }
    void fpu_dispatch(uint64_t cycle,uint32_t pc,uint16_t ir,const Registers& r,uint8_t state,uint8_t before_state,bool pipe_admit,bool pipe_rf_owner,uint32_t pipe_pc,bool fpu_enable) {
        fpu_last_cycle_=cycle;
        const uint8_t fc=(r.sr&0x2000)?6:2;
        uint16_t op=0;
        const bool known=word(pc,fc,op);
        ++dispatches_;if(known){++known_dispatches_;if(ir!=op) {
            ++ir_mismatch_;
            if(ir_mismatch_<=20) {
                out_<<"IR_MISMATCH cycle="<<cycle<<" pc="<<std::hex<<pc<<" ir="<<ir<<" fetched="<<op
                    <<std::dec<<" state="<<unsigned(state)<<" before_state="<<unsigned(before_state)
                    <<" pipe_admit="<<pipe_admit<<" pipe_rf_owner="<<pipe_rf_owner<<" pipe_pc="<<std::hex<<pipe_pc
                    <<std::dec<<'\n';out_.flush();
            }
        }}
        if(!fpu_enable)++secondary_skipped_;
        if(fpu_enable && known && ir!=op)++primary_mismatch_skipped_;
        if(!fpu_enable || (known && ir!=op)) {
            if(dispatches_==10000 || dispatches_%1000000==0)diagnostic_snapshot(cycle);
            return;
        }
        const unsigned before=fpu_prefix_;
        // Both immediate MOVE.W writes must be executed. The final 20-byte
        // signature is checked only after the JSR returns, when its next
        // opcode has been fetched. The third 18-byte prefix is duplicated
        // elsewhere in CODE3; its 20-byte form is unique in the pinned fork.
        if(fpu_prefix_==5 && pc==fpu_prefix_pc_+18) {
            const unsigned site=fpu_prefix_site_;
            uint32_t failed_pc=pc;
            const char* failure=!known?"OPCODE_UNKNOWN":op!=fpu_return_word_[site]?"RETURN_OPCODE_MISMATCH":
                r.a[5]!=fpu_prefix_a5_?"A5_CHANGED":"";
            const bool signature_ok=known && op==fpu_return_word_[site] && r.a[5]==fpu_prefix_a5_ &&
                fpu_signature(pc,fc,site,&failed_pc,&failure);
            if(signature_ok) {
                const uint32_t base=pc-fpu_prefix_return_[site];
                if(fpu_timer_||fpu_callback_||fpu_raw_pending_)
                    fpu_abort(cycle,"NEW_SITE_DURING_SPAN");
                if(fpu_identified_ && (base!=fpu_base_ || fc!=fpu_fc_))
                    fpu_drop_identity(cycle,"CODE3_RELOCATED");
                fpu_identified_=true;fpu_base_=base;fpu_fc_=fc;fpu_site_=site;
                fpu_event(FpuEvent::Identify,cycle,site);
                diagnostic(cycle,"IDENTIFY",pc);
            } else {++signature_failures_;diagnostic(cycle,"SIGNATURE_FAIL",failed_pc,failure,site);}
            fpu_prefix_=0;
        } else if(fpu_prefix_==4 && pc==fpu_prefix_pc_+12) {
            fpu_prefix_=known && op==0x4eb9 && r.a[5]==fpu_prefix_a5_ ? 5 : 0;
        } else if(fpu_prefix_!=5 && known && op==0x3b7c) {
            if(fpu_prefix_==2 && pc==fpu_prefix_pc_+6 && r.a[5]==fpu_prefix_a5_)
                fpu_prefix_=3;
            else {fpu_prefix_=1;fpu_prefix_pc_=pc;fpu_prefix_a5_=r.a[5];}
        }
        prefix_change(cycle,pc,before);
        if(dispatches_==10000 || dispatches_%1000000==0)diagnostic_snapshot(cycle);
        if(!fpu_identified_ || fc!=fpu_fc_)return;
        const unsigned site=fpu_site_;
        const uint32_t off=pc-fpu_base_;
        auto at=[&](uint32_t expected,uint16_t opcode) {return off==expected && known && op==opcode;};
        if(at(fpu_micro_start_[site],fpu_timer_return_word_[site]) ||
           at(fpu_fallback_start_[site],0x3f3c)) {
            if(fpu_timer_||fpu_callback_||fpu_raw_pending_)fpu_abort(cycle,"NESTED_TIMER_START");
            fpu_timer_=true;fpu_callback_complete_=false;
            fpu_microseconds_=off==fpu_micro_start_[site];
            ++fpu_starts_;
            const uint64_t raw=fpu_microseconds_?(uint64_t(r.a[0])<<32)|r.d[0]:0;
            fpu_event(FpuEvent::TimerStart,cycle,site,fpu_microseconds_,raw);
        } else if(at(fpu_call_[site],0x4e94)) {
            if(!fpu_timer_||fpu_callback_) {
                ++fpu_unmatched_;fpu_event(FpuEvent::Unmatched,cycle,site,false,0,"CALL_WITHOUT_TIMER");
                fpu_abort(cycle,"CALL_WITHOUT_TIMER");
            } else {
                fpu_callback_=true;++fpu_callbacks_;
                fpu_event(FpuEvent::CallbackStart,cycle,site,fpu_microseconds_);
            }
        } else if(at(fpu_return_[site],0x4a2d)) {
            if(!fpu_callback_) {
                ++fpu_unmatched_;fpu_event(FpuEvent::Unmatched,cycle,site,false,0,"RETURN_WITHOUT_CALL");
            } else {
                fpu_callback_=false;fpu_callback_complete_=true;++fpu_returns_;
                fpu_event(FpuEvent::CallbackStop,cycle,site,fpu_microseconds_);
            }
        } else if(at(fpu_micro_stop_[site],0xa193) ||
                  at(fpu_fallback_stop_[site],0x4eb9)) {
            const bool micro=off==fpu_micro_stop_[site];
            if(!fpu_timer_||fpu_callback_||!fpu_callback_complete_||
               micro!=fpu_microseconds_) {
                ++fpu_unmatched_;fpu_event(FpuEvent::Unmatched,cycle,site,micro,0,"STOP_WITHOUT_MATCHING_START");
                fpu_abort(cycle,"STOP_WITHOUT_MATCHING_START");
            } else {
                fpu_timer_=false;fpu_callback_complete_=false;
                fpu_raw_pending_=micro;++fpu_stops_;
                fpu_event(FpuEvent::TimerStop,cycle,site,micro);
            }
        } else if(fpu_raw_pending_ && at(fpu_micro_stop_return_[site],0x225f)) {
            fpu_raw_pending_=false;
            fpu_event(FpuEvent::TimerRawStop,cycle,site,true,(uint64_t(r.a[0])<<32)|r.d[0]);
        }
    }

    bool emit(const char* type,uint64_t cycle) {
        if(records_>=limit_) return false;
        ++records_;
        out_ << type << " cycle=" << cycle;
        return true;
    }
    void hex(const char* key,uint32_t v) { out_<<' '<<key<<"=0x"<<std::hex<<v<<std::dec; }
    const char* name() const { return test_==0?"Queens":"Sieve"; }
    static unsigned slot(uint32_t addr,uint8_t fc) { return (addr^(uint32_t(fc)<<8))&4095; }
    void put(uint32_t addr,uint8_t fc,uint8_t v) { code_[slot(addr,fc)]={addr,fc,v,true}; }
    bool get(uint32_t addr,uint8_t fc,uint8_t& v) const {
        const auto& b=code_[slot(addr,fc)];
        if(!b.valid || b.addr!=addr || b.fc!=fc) return false;
        v=b.value; return true;
    }
    bool word(uint32_t addr,uint8_t fc,uint16_t& v) const {
        uint8_t hi,lo;
        if(!get(addr,fc,hi)||!get(addr+1,fc,lo)) return false;
        v=uint16_t((hi<<8)|lo); return true;
    }
    bool signature(uint32_t pc,uint8_t fc,unsigned test) const {
        // Unique immutable non-relocated instruction/extension bytes. The
        // following JSR's relocated absolute address is intentionally omitted.
        const uint8_t s[]={0x3b,0x7c,0,4,0xbe,0xaa,0x3b,0x7c,0,
                           uint8_t(test?0xe2:0x92),0xbe,0xac};
        for(unsigned i=0;i<12;i++) { uint8_t b; if(!get(pc-12+i,fc,b)||b!=s[i]) return false; }
        return true;
    }
    void snapshot(const char* type,uint64_t cycle,uint32_t pc,uint16_t ir,const Registers& r) {
        if(!emit(type,cycle)) return;
        out_<<" test="<<name(); hex("pc",pc); hex("ir",ir); hex("base",base_); hex("sr",r.sr);
        for(unsigned i=0;i<8;i++) { std::string k="d"+std::to_string(i); hex(k.c_str(),r.d[i]); }
        for(unsigned i=0;i<8;i++) { std::string k="a"+std::to_string(i); hex(k.c_str(),r.a[i]); }
        out_<<" rf_pending="<<r.pending<<" aux_pending="<<r.aux;
        hex("pending_reg",r.pending_reg); hex("pending_data",r.pending_data);
        out_<<'\n';
    }
public:
    explicit Observer(std::ostream& out,uint64_t limit=512):limit_(limit),out_(out) {
        out_<<"META format=speedometer-observer-v1 clock_unit=33MHz_rising_edges limit="<<limit
            <<" resource_sha256=af67113bceb4eb906e973a9b747a0b1925b9d64c62f0f9a84bc6f0578839ca80\n";
    }
    bool bounded() const { return records_>=limit_; }
    uint64_t identities() const { return identities_; }
    void set_fpu_sink(std::function<void(const FpuEvent&)> sink) {fpu_sink_=std::move(sink);}
    void finish(uint64_t cycle) {fpu_abort(cycle,"CAPTURE_END");}
    uint64_t fpu_starts() const {return fpu_starts_;}
    uint64_t fpu_stops() const {return fpu_stops_;}
    uint64_t fpu_callbacks() const {return fpu_callbacks_;}
    uint64_t fpu_returns() const {return fpu_returns_;}
    uint64_t fpu_aborts() const {return fpu_aborts_;}
    uint64_t fpu_unmatched() const {return fpu_unmatched_;}
    uint64_t fpu_prefix_aborts() const {return fpu_prefix_aborts_;}
    void invalidate(uint64_t cycle,const char* reason) {
        fpu_drop_identity(cycle,reason);
        if(identified_ && emit("INVALIDATE",cycle))out_<<" reason="<<reason<<'\n';
        code_={};identified_=false;prefix_=0;
        have_start_=have_stop_=have_aggregate_=window_=false;
    }
    void reset(bool value) {
        if(value && !reset_) {fpu_drop_identity(fpu_last_cycle_,"RESET");
            context_valid_=false; identified_=false; code_={};prefix_=0;
            have_start_=have_stop_=have_aggregate_=window_=false; }
        reset_=value;
    }
    void context(const Context& c,uint64_t cycle) {
        if(!context_valid_ || !(context_==c)) {
            ++contexts_;invalidate(cycle,"MMU_REGISTERS");context_=c;context_valid_=true;
        }
    }
    void bus(const Bus& b) {
        if(!reset_ && b.ce && b.request) {
            ++request_samples_;
            if(b.ack){++ack_samples_;if(b.error)++error_acks_;
                else if(b.instruction&&!b.write){++instruction_acks_;fetched_bytes_+=b.bytes;}else ++data_acks_;}
        }
        if(reset_ || !b.ce || !b.request || !b.ack || b.error ||
           (b.bytes!=1 && b.bytes!=2 && b.bytes!=4)) return;
        if(b.instruction && !b.write) {
            for(unsigned i=0;i<b.bytes;i++) put(b.addr+i,b.fc,uint8_t(b.data>>(8*(b.bytes-1-i))));
            return;
        }
        if(b.write) {
            const unsigned before=fpu_prefix_;
            if(fpu_prefix_==1 && b.pc==fpu_prefix_pc_ &&
               b.addr==fpu_prefix_a5_-0x4156 && b.bytes==2 && uint16_t(b.data)==4)
                fpu_prefix_=2;
            else if(fpu_prefix_==3 && b.pc==fpu_prefix_pc_+6 &&
                    b.addr==fpu_prefix_a5_-0x4154 && b.bytes==2)
                for(unsigned site=0;site<3;site++)if(uint16_t(b.data)==fpu_selector_[site]) {
                    fpu_prefix_site_=site;fpu_prefix_=4;break;
                }
            prefix_change(b.cycle,b.pc,before);
            // Fresh EXECUTED prefix proof, not merely stale fetched bytes:
            // both MOVE.W instructions must actually write their known
            // immediate values at the known A5-relative logical addresses.
            if(prefix_==1 && b.pc==prefix_pc_ && b.addr==prefix_a5_-0x4156 && b.bytes==2 && uint16_t(b.data)==4)
                prefix_=2;
            else if(prefix_==3 && b.pc==prefix_pc_+6 && b.addr==prefix_a5_-0x4154 && b.bytes==2 &&
                    (uint16_t(b.data)==0x92 || uint16_t(b.data)==0xe2)) {
                prefix_test_=uint16_t(b.data)==0xe2;prefix_=4;
            }
            // Any logical write to a captured instruction invalidates it;
            // aliases may invalidate conservatively only when later fetched.
            for(unsigned i=0;i<b.bytes;i++) for(uint8_t fc: {uint8_t(2),uint8_t(6)}) {
                auto& x=code_[slot(b.addr+i,fc)];
                if(x.valid && x.addr==b.addr+i && x.fc==fc) x.valid=false;
            }
            if(fpu_identified_ && uint64_t(b.addr)<uint64_t(fpu_base_)+0x5408 &&
               uint64_t(b.addr)+b.bytes>uint64_t(fpu_base_)+0x4ec6)
                fpu_drop_identity(b.cycle,"CODE_WRITE");
        }
        if(bounded())return; // the FPU sink remains live after the legacy log cap
        if(!identified_ || !window_) return;
        const uint32_t selector=a5_-0x36f2, taskptr=a5_-0x205c, taskcount=a5_-0x6dfa;
        bool watched=false;
        for(unsigned i=0;i<b.bytes;i++) {
            const uint32_t addr=b.addr+i;
            watched|=addr==selector || uint32_t(addr-(a6_-16))<16 ||
                     uint32_t(addr-taskptr)<4 || uint32_t(addr-taskcount)<4;
            // Only the actual ADD.L -4(A6),D4 operand read supplies the
            // authoritative elapsed value; never infer it from backing RAM.
            const uint32_t aggregate=base_+(0x657a1-0x62561)+(test_?0x494:0);
            if(!b.write && b.pc==aggregate && uint32_t(addr-(a6_-4))<4) {
                const unsigned shift=8*(3-(addr-(a6_-4)));
                const uint32_t byte=(b.data>>(8*(b.bytes-1-i)))&255;
                elapsed_=(elapsed_&~(255u<<shift))|(byte<<shift);
                elapsed_mask_|=uint8_t(1u<<(addr-(a6_-4)));
            }
        }
        if(watched && emit("MEM",b.cycle)) {
            out_<<" test="<<name()<<" write="<<b.write<<" bytes="<<unsigned(b.bytes)<<" fc="<<unsigned(b.fc);
            hex("pc",b.pc);hex("logical",b.addr);hex("value",b.data);out_<<'\n';
        }
    }
    void dispatch(uint64_t cycle,uint32_t pc,uint16_t ir,const Registers& r,uint8_t state=255,uint8_t before_state=255,bool pipe_admit=false,bool pipe_rf_owner=false,uint32_t pipe_pc=0,bool fpu_enable=true) {
        if(reset_)return;
        fpu_dispatch(cycle,pc,ir,r,state,before_state,pipe_admit,pipe_rf_owner,pipe_pc,fpu_enable);
        if(bounded()) return;
        const uint8_t fc=(r.sr&0x2000)?6:2;
        const bool live_prefix=prefix_==4 && pc==prefix_pc_+12 && r.a[5]==prefix_a5_;
        const unsigned live_test=prefix_test_;
        if(ir==0x3b7c) {
            if(prefix_==2 && pc==prefix_pc_+6 && r.a[5]==prefix_a5_)prefix_=3;
            else {prefix_=1;prefix_pc_=pc;prefix_a5_=r.a[5];}
        } else prefix_=0;
        if(ir==0x4eb9 && live_prefix) for(unsigned t=0;t<2;t++) if(t==live_test && signature(pc,fc,t)) {
            test_=t; code_fc_=fc;
            base_=pc-((t?0x65bb1:0x65729)-0x62561);
            a5_=r.a[5];a6_=r.a[6]; identified_=true;++identities_;
            have_start_=have_stop_=have_aggregate_=window_=false;
            snapshot("IDENTIFY",cycle,pc,ir,r);
            if(emit("IDENTITY_CONTEXT",cycle)) {
                for(unsigned i=0;i<7;i++) {std::string k="mmu"+std::to_string(i);hex(k.c_str(),context_.mmu[i]);}
                out_<<" live_prefix_writes=2\n";
            }
        }
        if(!identified_) return;
        if((ir==0xa058 || ir==0xa059 || ir==0xa05a) && window_)
            snapshot("TIME_MANAGER_TRAP",cycle,pc,ir,r);
        if(fc!=code_fc_) return;
        const uint32_t offset=pc-base_-(test_?0x494:0);
        struct Point {uint32_t file;uint16_t opcode;const char* event;};
        const Point points[]={
          {0x65747,0x4a2d,"SELECT_START"},{0x65751,0xa193,"MICRO_START_CALL"},
          {0x65753,0x225f,"MICRO_START_RETURN"},{0x6575b,0x4eb9,"FALLBACK_START_CALL"},
          {0x65761,0x4eb9,"FALLBACK_PRIME_CALL"},{0x6576b,0x4eb9,"KERNEL_CALL"},
          {0x65771,0x4a2d,"KERNEL_RETURN"},{0x6577d,0xa193,"MICRO_STOP_CALL"},
          {0x6577f,0x225f,"MICRO_STOP_RETURN"},{0x6578d,0x4eb9,"SUBTRACT_CALL"},
          {0x65793,0x504f,"SUBTRACT_RETURN"},{0x65797,0x4eb9,"FALLBACK_STOP_CALL"},
          {0x6579d,0x2d40,"FALLBACK_STOP_RETURN"},{0x657a1,0xd8ae,"AGGREGATE_BEFORE"},
          {0x657a5,0x5285,"AGGREGATE_AFTER"},{0x657a7,0x594f,"COUNT_AFTER"},
          {0x657a9,0xa975,"TICK_CALL"},{0x657ab,0x201f,"TICK_RETURN_STACK"},
          {0x657ad,0xb08a,"TICK_COMPARE"},{0x657af,0x6590,"TICK_BRANCH"}};
        for(const auto& p:points) if(offset==p.file-0x62561) {
            if(ir!=p.opcode) {
                snapshot("IDENTITY_LOST",cycle,pc,ir,r);identified_=false;return;
            }
            a5_=r.a[5];a6_=r.a[6];
            if(p.file==0x65747) window_=true;
            if(p.file==0x6576b) {
                uint16_t op,selector;
                if(!word(pc-4,fc,op)||!word(pc-2,fc,selector)||op!=0x3f3c||selector!=(test_?12:6)) {
                    snapshot("KERNEL_SELECTOR_UNVERIFIED",cycle,pc,ir,r);
                    identified_=false;return;
                }
            }
            snapshot(p.event,cycle,pc,ir,r);
            if(p.file==0x65753) {
                start_=(uint64_t(r.a[0])<<32)|r.d[0];start_cycle_=cycle;
                have_start_=true;micro_start_=true;have_stop_=false;++starts_;
            }
            if(p.file==0x6575b) { have_start_=true;micro_start_=false;have_stop_=false;start_cycle_=cycle; }
            if(p.file==0x6577f) {
                stop_=(uint64_t(r.a[0])<<32)|r.d[0];stop_cycle_=cycle;have_stop_=true;++stops_;
                if(have_start_ && micro_start_ && emit("RAW_DELTA",cycle)) {
                    out_<<" test="<<name()<<" start="<<start_<<" stop="<<stop_
                        <<" delta_u64="<<(stop_-start_)<<" backwards="<<(stop_<start_)
                        <<" observed_cycles="<<(stop_cycle_-start_cycle_)<<'\n';
                }
            }
            if(p.file==0x657a1) {before_d4_=r.d[4];have_aggregate_=true;elapsed_=0;elapsed_mask_=0;}
            if(p.file==0x657a5 && have_aggregate_ && emit("AGGREGATE_CHECK",cycle)) {
                out_<<" test="<<name()<<" elapsed_read_valid="<<(elapsed_mask_==15);
                hex("guest_elapsed",elapsed_);hex("d4_before",before_d4_);hex("d4_after",r.d[4]);
                out_<<" sum_matches="<<(elapsed_mask_==15 && r.d[4]==uint32_t(before_d4_+elapsed_));
                if(have_start_&&micro_start_&&have_stop_)out_<<" raw_low32_matches="<<(elapsed_mask_==15&&elapsed_==uint32_t(stop_-start_));
                out_<<'\n';
            }
            if(p.file==0x657af) {
                window_=false;
                // BCS repeats this exact bracket only while C=1. Once the
                // test falls through, require a newly executed setup prefix.
                if(!(r.sr&1))identified_=false;
            }
            return;
        }
    }
    uint64_t instruction_acks() const {return instruction_acks_;}
    uint64_t known_dispatches() const {return known_dispatches_;}
    uint64_t dispatches() const {return dispatches_;}
    void diagnostic_snapshot(uint64_t cycle) {
        out_<<"ADAPTER cycle="<<cycle<<" request_samples="<<request_samples_<<" ack_samples="<<ack_samples_
            <<" instruction_acks="<<instruction_acks_<<" data_acks="<<data_acks_<<" error_acks="<<error_acks_
            <<" fetched_bytes="<<fetched_bytes_<<" dispatches="<<dispatches_<<" known_dispatches="<<known_dispatches_
            <<" ir_mismatch="<<ir_mismatch_<<" signature_failures="<<signature_failures_<<" secondary_skipped="<<secondary_skipped_<<" primary_mismatch_skipped="<<primary_mismatch_skipped_
            <<" diagnostic_dropped="<<diag_dropped_<<" starts="<<fpu_starts_<<" stops="<<fpu_stops_
            <<" callbacks="<<fpu_callbacks_<<" returns="<<fpu_returns_<<" aborts="<<fpu_aborts_
            <<" unmatched="<<fpu_unmatched_<<" prefix_aborts="<<fpu_prefix_aborts_;
        for(unsigned i=0;i<6;i++)out_<<" prefix"<<i<<'='<<prefix_transitions_[i];
        for(unsigned i=0;i<6;i++)out_<<" invalidation"<<i<<'='<<invalidations_[i];
        out_<<'\n';
        for(unsigned reason=0;reason<6;reason++) {
            out_<<"INVALIDATIONS cycle="<<cycle<<" reason="<<reason;
            for(unsigned phase=0;phase<6;phase++)out_<<" phase"<<phase<<'='<<invalidation_phases_[reason][phase];
            out_<<'\n';
        }
        out_.flush();
    }
    void summary() {
        diagnostic_snapshot(fpu_last_cycle_);
        out_<<"FPU_SUMMARY starts="<<fpu_starts_<<" stops="<<fpu_stops_
            <<" callbacks="<<fpu_callbacks_<<" returns="<<fpu_returns_
            <<" aborts="<<fpu_aborts_<<" unmatched="<<fpu_unmatched_
            <<" prefix_aborts="<<fpu_prefix_aborts_
            <<" timer_open="<<fpu_timer_<<" callback_open="<<fpu_callback_
            <<" raw_stop_pending="<<fpu_raw_pending_<<'\n';
        out_<<"SUMMARY records="<<records_<<" identities="<<identities_<<" micro_starts="<<starts_
            <<" micro_stops="<<stops_<<" contexts="<<contexts_<<" capped="<<bounded()<<'\n';out_.flush();
    }
};
}
#endif
