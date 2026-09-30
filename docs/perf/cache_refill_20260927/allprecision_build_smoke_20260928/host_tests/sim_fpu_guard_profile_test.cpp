#include "sim_fpu_guard_profile.h"
#include "cpu_dispatch_observer.h"
#include <cassert>
#include <string>
int main() {
    SimFpuGuardEdge s; s.nreset=true; s.req=true; s.opclass=2; s.format=1; s.exponent=127;
    SimFpuGuardProfile p;
    for(unsigned precision=0;precision<4;++precision) for(unsigned enables=0;enables<256;++enables) {
        s.fpcr=(precision<<6)|(enables<<8); p.sample(s,14);
        const auto& b=p.buckets[precision][enables];
        assert(b.raw==1 && b.single==1 && b.normal==1);
        assert(b.newguard==(enables==0)); assert(b.oldguard==(enables==0&&precision==0));
    }
    assert(p.reconciles() && p.edges==1024 && p.context_count==64 && p.context_dropped==960);
    assert(p.normal_enable_rejected==1020);
    p.reset(); s.fpcr=0;
    for(unsigned bit=0;bit<8;++bit) {s.sideports=1<<bit;p.sample(s,14);assert(p.side_rejected[bit]==1);}
    assert(p.buckets[0][0].normal==8 && p.buckets[0][0].newguard==0);
    s.sideports=0;s.exponent=0;p.sample(s,14);s.exponent=255;p.sample(s,14);
    assert(p.buckets[0][0].zero==1&&p.buckets[0][0].allones==1);
    s.exponent=1;s.opclass=1;p.sample(s,14);assert(p.unexpected_single_class==1&&p.buckets[0][0].newguard==1);
    for(unsigned c:{0u,3u}) {s.opclass=c;p.sample(s,14);}
    s.opclass=2;s.format=2;p.sample(s,14);s.format=1;s.opmode=4;p.sample(s,14);s.opmode=0;
    const auto before=p.raw;
    s.fst=1;p.sample(s,14);s.fst=0;s.ce=false;p.sample(s,14);s.ce=true;s.nreset=false;p.sample(s,14);s.nreset=true;
    s.restore_unimp=true;s.restore_resume=true;p.sample(s,14);s.restore_unimp=false;s.restore_resume=false;
    s.state_unimp=true;s.state_resig=true;p.sample(s,14);assert(p.raw==before&&p.restore==1&&p.pending==1);
    s.state_e1=true;p.sample(s,14);assert(p.raw==before+1);s.state_unimp=false;s.state_e1=false;s.state_resig=false;
    // Held req counts again only on a new IDLE branch edge; busy samples do not.
    auto raw=p.raw;p.sample(s,14);s.fst=14;p.sample(s,14);s.fst=0;p.sample(s,14);assert(p.raw==raw+2);
    assert(p.reconciles());
    // Apply the exact existing gate ordering: snapshot before state changes,
    // reset on Start then count it, Skip/Stop excluded, restart clears history.
    CpuProfileGate gate;p.reset();
    auto step=[&](bool start,bool stop,const SimFpuGuardEdge& edge) {
        auto a=gate.sample(start,stop);if(a==CpuProfileGate::Start)p.reset();
        if(a==CpuProfileGate::Start||a==CpuProfileGate::Count)p.sample(edge,14);
    };
    step(false,false,s);assert(p.edges==0);
    SimFpuGuardEdge saved=s;saved.fpcr=64;s.fpcr=0;
    step(true,false,saved);step(false,false,s);step(false,true,s);
    assert(p.edges==2&&p.raw==2&&p.buckets[1][0].newguard==1&&p.buckets[1][0].oldguard==0);
    step(false,false,s);assert(p.edges==2);
    step(true,true,s);assert(p.edges==1&&p.buckets[0][0].oldguard==1);
    FILE* f=tmpfile();assert(f);p.dump(f);rewind(f);std::string report;char buf[512];while(fgets(buf,sizeof(buf),f))report+=buf;fclose(f);
    assert(report.find("FPU_GUARD_SUMMARY\t1\t1\t0\t0\t0\t0\t0\t1\t0\t1")!=std::string::npos);
    assert(report.find("FPU_GUARD_BUCKET\t0\t0\t1\t1\t0\t1\t0\t1\t1")!=std::string::npos);
    p.sample(s,1);assert(p.eligible_post_mismatch==1 && !p.reconciles());
    puts("PASS guard observer exact predicates/FPCR buckets/ports/priority/heldreq/bounded context/window/snapshot/report");
}
