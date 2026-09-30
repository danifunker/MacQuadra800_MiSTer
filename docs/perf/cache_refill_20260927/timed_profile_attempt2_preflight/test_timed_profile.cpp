#include "fpu_timed_profile.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

int main(int argc,char** argv) {
    assert(argc==2);
    FpuTimedProfile p(argv[1]);
    using E=speedometer::FpuEvent;
    auto event=[&](E::Kind kind,uint64_t cycle,unsigned site=0,bool micro=true,
                   uint64_t raw=0,const char* reason="") {
        p.event(E{kind,cycle,site,micro,raw,reason});
    };
    WindowSample s;
    s.core_state=153;s.cache_state=4;s.fpu_state=9;s.fpu_op=2;
    s.fpu_bg=true;s.fpu_done=false;s.dispatch=true;s.fill_acked=false;
    event(E::Identify,9);
    for(unsigned repeat=0;repeat<2;++repeat) {
        const uint64_t t=10+10*repeat;
        event(E::TimerStart,t,0,true,100+100*repeat);
        p.sample(s);                           // start inclusive
        event(E::CallbackStart,t+1);
        p.sample(s);                           // in both spans
        event(E::CallbackStop,t+2);
        p.sample(s);                           // callback end exclusive
        event(E::TimerStop,t+3);
        event(E::TimerRawStop,t+4,0,true,140+110*repeat);
    }
    event(E::TimerStart,30);
    p.sample(s);
    event(E::Abort,31,0,true,0,"PFLUSH_OR_CINV");
    event(E::TimerStart,40,0,true,300);
    event(E::CallbackStart,41);
    p.sample(s);
    event(E::CallbackStop,42);
    event(E::TimerStop,43);
    event(E::Abort,44,0,true,0,"CAPTURE_END"); // completed span, missing raw stop
    event(E::TimerStart,50,1);
    p.sample(s);
    event(E::Abort,51,1,true,0,"CAPTURE_END"); // observer finish() equivalent
    assert(p.dump());
    assert(p.dump());                            // idempotent
    std::ifstream file(argv[1]);
    const std::string report((std::istreambuf_iterator<char>(file)),{});
    auto has=[&](const std::string& x){assert(report.find(x)!=std::string::npos);};
    has("SPAN\t0\ttimer\tstarts=4\tcomplete=3\taborted=1\topen=0");
    has("SPAN\t0\tcallback\tstarts=3\tcomplete=3\taborted=0\topen=0");
    has("TOTAL\t0\ttimer\tcomplete\t7\t7\t7\t7\t0\t0\t0");
    has("TOTAL\t0\tcallback\tcomplete\t3\t3\t3\t3\t0\t0\t0");
    has("TOTAL\t0\ttimer\tpartial\t1\t1\t1\t1\t0\t0\t0");
    has("LIFECYCLE\t0\tidentifies=1\tunmatched=0\traw_pairs=2\traw_missing=1");
    has("RAW\t0\t100\t140\t40\t0\t10\t14");
    has("RAW\t0\t200\t250\t50\t0\t20\t24");
    has("SPAN\t1\ttimer\tstarts=1\tcomplete=0\taborted=1\topen=0");
    has("DIAG\t0\t31\tabort\tPFLUSH_OR_CINV");
    has("DIAG\t0\t44\tabort\tCAPTURE_END");
    std::cout<<"PASS timed profile boundaries, aggregate, partial, raw pairs and capture-end diagnosis\n";
}
