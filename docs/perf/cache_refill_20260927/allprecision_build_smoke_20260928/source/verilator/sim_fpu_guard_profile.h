#ifndef SIM_FPU_GUARD_PROFILE_H
#define SIM_FPU_GUARD_PROFILE_H
#include <array>
#include <cstdint>
#include <cstdio>

// Stable inputs consumed by the upcoming enabled FPU edge. No request-episode
// deduplication: these count execution of new_fp_command, not retirements.
struct SimFpuGuardEdge {
    bool nreset=false, ce=true, req=false, restore_unimp=false, restore_resume=false;
    bool state_unimp=false, state_e1=false, state_resig=false;
    uint8_t fst=0, opclass=0, format=0, opmode=0, exponent=0, sideports=0;
    uint32_t fpcr=0, pc=0;
};
class SimFpuGuardProfile {
public:
    struct Bucket { uint64_t raw=0, single=0, zero=0, normal=0, allones=0, oldguard=0, newguard=0; };
    struct Context { uint64_t edge; uint32_t pc, fpcr; uint8_t opclass, sideports; bool oldguard,newguard; };
    std::array<std::array<Bucket,256>,4> buckets{};
    std::array<uint64_t,8> side_rejected{};
    std::array<Context,64> contexts{};
    uint64_t edges=0, raw=0, restore=0, pending=0, unexpected_single_class=0;
    uint64_t normal_enable_rejected=0, context_count=0, context_dropped=0;
    uint64_t eligible_post_round=0, eligible_post_mismatch=0;
    void reset() { *this=SimFpuGuardProfile{}; }
    void sample(const SimFpuGuardEdge& s, uint8_t post_fst) {
        ++edges;
        if (!s.nreset || !s.ce || s.fst!=0) return;
        if (s.restore_unimp && s.restore_resume) { ++restore; return; }
        if (!s.req) return;
        if (s.state_unimp && !s.state_e1 && s.state_resig) { ++pending; return; }
        const unsigned precision=(s.fpcr>>6)&3, enables=(s.fpcr>>8)&255;
        auto& b=buckets[precision][enables]; ++raw; ++b.raw;
        // This mirrors the actual final memory-source else, rather than
        // assuming the core only supplies class010. For fmt1/op0 the earlier
        // FMOVECR/unimplemented/packed branches do not intercept the command.
        if (s.opclass==0 || s.opclass==3 || s.format!=1 || s.opmode!=0) return;
        ++b.single; if(s.opclass!=2) ++unexpected_single_class;
        if(s.exponent==0) { ++b.zero; return; }
        if(s.exponent==255) { ++b.allones; return; }
        ++b.normal;
        const bool eligible=enables==0 && s.sideports==0;
        const bool old=eligible && precision==0;
        b.newguard+=eligible; b.oldguard+=old;
        if(eligible) { if(post_fst==14) ++eligible_post_round; else ++eligible_post_mismatch; }
        normal_enable_rejected+=enables!=0;
        for(unsigned i=0;i<8;++i) side_rejected[i]+=(s.sideports>>i)&1;
        if(context_count<contexts.size()) contexts[context_count++]={edges,s.pc,s.fpcr,s.opclass,s.sideports,old,eligible};
        else ++context_dropped;
    }
    bool reconciles() const {
        uint64_t total=0, eligible=0;
        for(const auto& p:buckets) for(const auto& b:p) {
            if(b.single!=b.zero+b.normal+b.allones || b.oldguard>b.newguard || b.newguard>b.normal || b.single>b.raw) return false;
            total+=b.raw; eligible+=b.newguard;
        }
        return total==raw && raw+restore+pending<=edges && eligible==eligible_post_round+eligible_post_mismatch && eligible_post_mismatch==0;
    }
    void dump(FILE* f) const {
        fprintf(f,"FPU_GUARD_META\tformat\tfpu-guard-profile-v1\n");
        fprintf(f,"FPU_GUARD_META\tsample\tpre_eval_inputs_committed_start_inclusive_stop_exclusive\n");
        fprintf(f,"FPU_GUARD_META\tcounts\tnew_fp_command_branch_events_not_retirements_or_unique_requests\n");
        fprintf(f,"FPU_GUARD_META\tside_bits\tcr_we,fm_we,bsun_req,fp_reset,frestore_idle,frestore_unimp,fsave_ack,pend_capture\n");
        fprintf(f,"FPU_GUARD_SUMMARY\tedges\traw\trestore\tpending\tunexpected_single_class\tenable_rejected_normal\tcontext_dropped\teligible_post_round\teligible_post_mismatch\treconciles\n");
        fprintf(f,"FPU_GUARD_SUMMARY\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%d\n",(unsigned long long)edges,(unsigned long long)raw,(unsigned long long)restore,(unsigned long long)pending,(unsigned long long)unexpected_single_class,(unsigned long long)normal_enable_rejected,(unsigned long long)context_dropped,(unsigned long long)eligible_post_round,(unsigned long long)eligible_post_mismatch,reconciles());
        fprintf(f,"FPU_GUARD_BUCKET\tprecision\tenables\traw\tsingle\texp_zero\texp_normal\texp_allones\told_guard\tnew_guard\n");
        for(unsigned p=0;p<4;++p) for(unsigned e=0;e<256;++e) { const auto& b=buckets[p][e]; if(b.raw)
            fprintf(f,"FPU_GUARD_BUCKET\t%u\t%u\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\n",p,e,(unsigned long long)b.raw,(unsigned long long)b.single,(unsigned long long)b.zero,(unsigned long long)b.normal,(unsigned long long)b.allones,(unsigned long long)b.oldguard,(unsigned long long)b.newguard);
        }
        for(unsigned i=0;i<8;++i) fprintf(f,"FPU_GUARD_REJECT_SIDE\t%u\t%llu\n",i,(unsigned long long)side_rejected[i]);
        fprintf(f,"FPU_GUARD_CONTEXT\tprofile_edge\tpc\tfpcr\topclass\tside_bits\told_guard\tnew_guard\n");
        for(unsigned i=0;i<context_count;++i) { const auto& c=contexts[i]; fprintf(f,"FPU_GUARD_CONTEXT\t%llu\t%08X\t%08X\t%u\t%u\t%d\t%d\n",(unsigned long long)c.edge,c.pc,c.fpcr,c.opclass,c.sideports,c.oldguard,c.newguard); }
    }
};
#endif
