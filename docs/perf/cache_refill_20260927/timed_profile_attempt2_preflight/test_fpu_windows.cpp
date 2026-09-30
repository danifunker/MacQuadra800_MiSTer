#include "speedometer_observer.h"
#include <cassert>
#include <fstream>
#include <sstream>
#include <vector>
#include <iostream>
using namespace speedometer;

static constexpr uint32_t base=0x81234000, code_file=0x62561;
static constexpr uint32_t prefix[3]={0x4f4a,0x50bc,0x527a};
static constexpr uint32_t start_micro[3]={0x4f68,0x50f2,0x52b0};
static constexpr uint32_t start_fallback[3]={0x4f7c,0x5106,0x52c4};
static constexpr uint32_t call[3]={0x4f80,0x510a,0x52c8};
static constexpr uint32_t ret[3]={0x4f82,0x510c,0x52ca};
static constexpr uint32_t stop_micro[3]={0x4f8e,0x5118,0x52d6};
static constexpr uint32_t stop_fallback[3]={0x4fa8,0x5132,0x52f0};
static constexpr uint16_t selector[3]={0x24,0x42,0x56};
static std::vector<unsigned char> resource;

static uint16_t word(uint32_t off) {
    return (uint16_t(resource[code_file+off])<<8)|resource[code_file+off+1];
}
static Registers regs() {Registers r;r.sr=0x2000;r.a[5]=0x92345000;return r;}
static void fetch(Observer& o,uint32_t off) {
    const uint32_t aligned=off&~3u;
    Bus b;b.addr=base+aligned;b.fc=6;b.bytes=4;b.request=b.ack=b.instruction=true;
    for(unsigned i=0;i<4;i++)b.data=(b.data<<8)|resource[code_file+aligned+i];
    o.bus(b);
}
static void fetch_range(Observer& o,uint32_t first,uint32_t last) {
    for(uint32_t off=first&~3u;off<last;off+=4)fetch(o,off);
}
static void dispatch(Observer& o,uint64_t cycle,uint32_t off,const Registers& r) {
    fetch(o,off);o.dispatch(cycle,base+off,word(off),r);
}
static void write(Observer& o,uint64_t cycle,uint32_t off,uint32_t addr,uint16_t data) {
    Bus b;b.cycle=cycle;b.pc=base+off;b.addr=addr;b.data=data;b.bytes=2;b.fc=5;
    b.request=b.ack=b.write=true;o.bus(b);
}
static void identify(Observer& o,unsigned site,uint64_t cycle,const Registers& r) {
    const uint32_t p=prefix[site];
    fetch_range(o,p,p+20);
    dispatch(o,cycle,p,r);
    write(o,cycle,p,r.a[5]-0x4156,4);
    dispatch(o,cycle+1,p+6,r);
    write(o,cycle+1,p+6,r.a[5]-0x4154,selector[site]);
    dispatch(o,cycle+2,p+12,r);
    // Helper instructions between the JSR and its return must not reset the
    // pending identity proof.
    o.dispatch(cycle+3,0x40801234,0x3b7c,r);
    dispatch(o,cycle+4,p+18,r);
}
static void exhaust_legacy_log(Observer& o,Registers r) {
    const uint32_t p=0x31bc;
    fetch_range(o,p,p+12);
    dispatch(o,2,p,r);write(o,2,p,r.a[5]-0x4156,4);
    dispatch(o,3,p+6,r);write(o,3,p+6,r.a[5]-0x4154,0x92);
    dispatch(o,4,p+12,r);
    assert(o.bounded());
}
static void complete(Observer& o,unsigned site,uint64_t cycle,bool micro,Registers r) {
    if(micro){r.a[0]=1;r.d[0]=0x100;}
    dispatch(o,cycle,micro?start_micro[site]:start_fallback[site],r);
    dispatch(o,cycle+1,call[site],r);
    dispatch(o,cycle+6,ret[site],r);
    dispatch(o,cycle+7,micro?stop_micro[site]:stop_fallback[site],r);
    if(micro){r.a[0]=1;r.d[0]=0x200;dispatch(o,cycle+8,stop_micro[site]+2,r);}
}
int main(int argc,char** argv) {
    assert(argc==2);
    std::ifstream f(argv[1],std::ios::binary);
    resource.assign(std::istreambuf_iterator<char>(f),{});
    assert(resource.size()>code_file+0x5408);
    {
        std::ostringstream log;Observer o(log,1);std::vector<FpuEvent> e;
        o.set_fpu_sink([&](const FpuEvent& x){e.push_back(x);});
        auto r=regs();exhaust_legacy_log(o,r);identify(o,0,10,r);
        complete(o,0,20,true,r);
        identify(o,0,40,r);complete(o,0,50,true,r);
        identify(o,1,70,r);complete(o,1,80,false,r);
        // A loader-relocated absolute JSR target must not break identity.
        const auto saved=std::vector<unsigned char>(resource.begin()+code_file+prefix[2]+14,
                                                    resource.begin()+code_file+prefix[2]+18);
        const unsigned char relocated[]={0x12,0x34,0x56,0x78};
        for(unsigned i=0;i<4;i++)resource[code_file+prefix[2]+14+i]=relocated[i];
        identify(o,2,100,r);complete(o,2,110,true,r);
        for(unsigned i=0;i<4;i++)resource[code_file+prefix[2]+14+i]=saved[i];
        o.finish(130);o.summary();
        assert(o.fpu_starts()==4 && o.fpu_stops()==4);
        assert(o.fpu_callbacks()==4 && o.fpu_returns()==4);
        assert(o.fpu_aborts()==0 && o.fpu_unmatched()==0);
        assert(e.size()==4*5+3); // identify + timer/callback pair, plus raw-stop on micro
        unsigned ids[3]={0,0,0},micro_raw=0;
        for(const auto& x:e){
            if(x.kind==FpuEvent::Identify)ids[x.site]++;
            if(x.kind==FpuEvent::TimerRawStop){micro_raw++;assert(x.raw==0x100000200ull);}
        }
        assert(ids[0]==2 && ids[1]==1 && ids[2]==1 && micro_raw==3);
        assert(log.str().find("FPU_SUMMARY starts=4 stops=4 callbacks=4 returns=4 aborts=0 unmatched=0")!=std::string::npos);
    }
    {
        std::ostringstream log;Observer o(log);std::vector<FpuEvent> e;
        o.set_fpu_sink([&](const FpuEvent& x){e.push_back(x);});auto r=regs();
        identify(o,0,10,r);
        dispatch(o,20,start_micro[0],r);
        dispatch(o,21,call[0],r);
        o.invalidate(22,"PFLUSH_OR_CINV");
        assert(o.fpu_aborts()==1 && e.back().kind==FpuEvent::Abort);
        assert(std::string(e.back().reason)=="PFLUSH_OR_CINV");
        dispatch(o,23,ret[0],r);assert(o.fpu_returns()==0);
        identify(o,2,30,r);complete(o,2,40,false,r);
        assert(o.fpu_stops()==1 && o.fpu_returns()==1);
        // A second incomplete capture is explicitly aborted at profile end.
        identify(o,1,50,r);dispatch(o,60,start_fallback[1],r);
        o.finish(61);assert(o.fpu_aborts()==2);
        assert(std::string(e.back().reason)=="CAPTURE_END");
    }
    {
        std::ostringstream log;Observer o(log);auto r=regs();identify(o,1,10,r);
        dispatch(o,20,ret[1],r);dispatch(o,21,stop_micro[1],r);
        assert(o.fpu_unmatched()==2 && o.fpu_stops()==0);
        identify(o,1,30,r);dispatch(o,40,start_micro[1],r);
        // Same-root MMU/PTE invalidation clears identity and records partial.
        Context c;c.mmu[0]=0x8000;o.context(c,41);
        assert(o.fpu_aborts()==1 && o.fpu_stops()==0);
    }
    {
        std::ostringstream log;Observer o(log);std::vector<FpuEvent> e;
        o.set_fpu_sink([&](const FpuEvent& x){e.push_back(x);});auto r=regs();
        identify(o,0,10,r);dispatch(o,20,start_micro[0],r);dispatch(o,21,call[0],r);
        identify(o,1,30,r);
        assert(o.fpu_aborts()==1 && std::string(e[e.size()-2].reason)=="NEW_SITE_DURING_SPAN");
        complete(o,1,40,false,r);
        assert(o.fpu_stops()==1 && o.fpu_returns()==1);
        // A timer start/stop without a callback is a partial window.
        identify(o,2,50,r);dispatch(o,60,start_micro[2],r);dispatch(o,61,stop_micro[2],r);
        assert(o.fpu_stops()==1 && o.fpu_aborts()==2 && o.fpu_unmatched()==1);
        // A multi-byte write crossing the first byte of CODE3 invalidates.
        identify(o,0,70,r);dispatch(o,80,start_micro[0],r);
        write(o,81,0,r.a[5]-0x4156,4); // unrelated data write keeps the identity
        Bus b;b.cycle=82;b.pc=0x1234;b.addr=base+0x4ec5;b.data=0xffff;
        b.bytes=2;b.fc=5;b.request=b.ack=b.write=true;o.bus(b);
        assert(o.fpu_aborts()==3 && std::string(e.back().reason)=="CODE_WRITE");
    }
    {
        std::ostringstream log;Observer o(log);auto r=regs();
        const uint32_t p=prefix[0];
        fetch_range(o,p,p+20);
        dispatch(o,10,p,r);write(o,10,p,r.a[5]-0x4156,4);
        dispatch(o,11,p+6,r);write(o,11,p+6,r.a[5]-0x4154,selector[0]);
        dispatch(o,12,p+12,r);
        o.invalidate(13,"PFLUSH_OR_CINV");
        assert(o.fpu_prefix_aborts()==1);
        identify(o,0,20,r);
        dispatch(o,30,p,r);write(o,30,p,r.a[5]-0x4156,4);
        dispatch(o,31,p+6,r);write(o,31,p+6,r.a[5]-0x4154,selector[0]);
        dispatch(o,32,p+12,r);
        o.invalidate(33,"PFLUSH_OR_CINV");
        assert(o.fpu_prefix_aborts()==2); // sticky previous identity cannot hide it
    }
    {
        std::ostringstream log;Observer o(log);auto r=regs();
        // Exhaust generic boot-like diagnostics before a qualified site.
        for(unsigned i=0;i<2200;i++) {
            dispatch(o,i*2,prefix[0],r);
            o.invalidate(i*2+1,"PFLUSH_OR_CINV");
        }
        identify(o,1,5000,r);complete(o,1,5010,false,r);o.summary();
        assert(log.str().find("kind=PREFIX phase=4 site=1")!=std::string::npos);
        assert(log.str().find("kind=FPU_TimerStop")!=std::string::npos);
        assert(log.str().find("diagnostic_dropped=0")==std::string::npos);
        assert(o.fpu_starts()==1 && o.fpu_stops()==1);
    }
    std::cout<<"PASS pinned CODE3 runtime relocation, 3 sites, repeated timer/callback spans, fallback, raw Microseconds, invalidation and partial capture\n";
}
