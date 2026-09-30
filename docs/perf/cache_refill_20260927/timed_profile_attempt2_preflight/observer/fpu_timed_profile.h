#ifndef FPU_TIMED_PROFILE_H
#define FPU_TIMED_PROFILE_H

#include "window_counters.h"
#include "speedometer_observer.h"
#include <array>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

// Simulation-only accumulation of observer-validated CODE3 intervals.
// A span starts on a dispatch after the start timer trap returns, and ends
// before the stop trap dispatch. Callback spans bracket JSR(A4) and return.
// Aborted samples never enter complete totals.
class FpuTimedProfile {
    struct Span {
        WindowCounters current{},complete{},partial{};
        uint64_t starts=0,stops=0,aborts=0;
        bool open=false;
    };
    struct Site {
        Span timer,callback;
        uint64_t identifies=0,unmatched=0,raw_pairs=0,raw_missing=0;
        bool raw_pending=false,micro=false;
        uint64_t raw_start=0,raw_start_cycle=0;
    };
    struct Raw {unsigned site;uint64_t start,stop,start_cycle,stop_cycle;};
    struct Diagnostic {unsigned site;uint64_t cycle;const char* kind;std::string reason;};
    std::array<Site,3> site_{};
    std::vector<Raw> raw_;
    std::vector<Diagnostic> diagnostics_;
    static constexpr size_t raw_cap_=4096;
    uint64_t raw_dropped_=0,invalid_samples_=0;
    uint64_t diagnostic_dropped_=0;
    std::string path_;
    bool dumped_=false;
    static void add(WindowCounters& a,const WindowCounters& b) {
        a.total+=b.total;a.dispatched+=b.dispatched;
        for(size_t i=0;i<a.core.size();++i)a.core[i]+=b.core[i];
        for(size_t i=0;i<a.cache.size();++i)a.cache[i]+=b.cache[i];
        for(size_t i=0;i<a.fpu.size();++i)a.fpu[i]+=b.fpu[i];
        for(size_t i=0;i<a.fpu_op_busy.size();++i)a.fpu_op_busy[i]+=b.fpu_op_busy[i];
        a.bg_samples+=b.bg_samples;a.blocking_decode+=b.blocking_decode;
        a.go_samples+=b.go_samples;a.mrd_fill_overlap+=b.mrd_fill_overlap;
        a.mrd_fill_unacked_overlap+=b.mrd_fill_unacked_overlap;
    }
    static void start(Span& s) {s.current.reset();s.open=true;++s.starts;}
    static void stop(Span& s) {
        if(!s.open)return;
        add(s.complete,s.current);s.current.reset();s.open=false;++s.stops;
    }
    static void abort(Span& s) {
        if(!s.open)return;
        add(s.partial,s.current);s.current.reset();s.open=false;++s.aborts;
    }
    static void counters(FILE* f,unsigned site,const char* span,const char* status,
                         const WindowCounters& c) {
        fprintf(f,"TOTAL\t%u\t%s\t%s\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu\n",
                site,span,status,(unsigned long long)c.total,(unsigned long long)c.dispatched,
                (unsigned long long)c.bg_samples,(unsigned long long)c.blocking_decode,
                (unsigned long long)c.go_samples,(unsigned long long)c.mrd_fill_overlap,
                (unsigned long long)c.mrd_fill_unacked_overlap);
        for(unsigned i=0;i<c.core.size();++i)if(c.core[i])
            fprintf(f,"CORE\t%u\t%s\t%s\t%u\t%llu\n",site,span,status,i,(unsigned long long)c.core[i]);
        for(unsigned i=0;i<c.cache.size();++i)if(c.cache[i])
            fprintf(f,"CACHE\t%u\t%s\t%s\t%u\t%llu\n",site,span,status,i,(unsigned long long)c.cache[i]);
        for(unsigned i=0;i<c.fpu.size();++i)if(c.fpu[i])
            fprintf(f,"FPU_FST\t%u\t%s\t%s\t%u\t%llu\n",site,span,status,i,(unsigned long long)c.fpu[i]);
        for(unsigned i=0;i<c.fpu_op_busy.size();++i)if(c.fpu_op_busy[i])
            fprintf(f,"FPU_OP_BUSY\t%u\t%s\t%s\t%u\t%llu\n",site,span,status,i,(unsigned long long)c.fpu_op_busy[i]);
    }
public:
    explicit FpuTimedProfile(std::string path):path_(std::move(path)) {
        raw_.reserve(raw_cap_);diagnostics_.reserve(raw_cap_);
    }
    void event(const speedometer::FpuEvent& e) {
        if(e.site>=site_.size())return;
        if(e.kind==speedometer::FpuEvent::Identify ||
           e.kind==speedometer::FpuEvent::Abort ||
           e.kind==speedometer::FpuEvent::Unmatched) {
            if(diagnostics_.size()<raw_cap_)
                diagnostics_.push_back({e.site,e.cycle,
                    e.kind==speedometer::FpuEvent::Identify?"identify":
                    e.kind==speedometer::FpuEvent::Abort?"abort":"unmatched",e.reason});
            else ++diagnostic_dropped_;
        }
        Site& s=site_[e.site];
        switch(e.kind) {
        case speedometer::FpuEvent::Identify: ++s.identifies;break;
        case speedometer::FpuEvent::TimerStart:
            start(s.timer);s.micro=e.microseconds;s.raw_start=e.raw;s.raw_start_cycle=e.cycle;break;
        case speedometer::FpuEvent::CallbackStart:start(s.callback);break;
        case speedometer::FpuEvent::CallbackStop:stop(s.callback);break;
        case speedometer::FpuEvent::TimerStop:stop(s.timer);s.raw_pending=e.microseconds;break;
        case speedometer::FpuEvent::TimerRawStop:
            if(s.raw_pending) {
                ++s.raw_pairs;
                if(raw_.size()<raw_cap_)raw_.push_back({e.site,s.raw_start,e.raw,s.raw_start_cycle,e.cycle});
                else ++raw_dropped_;
                s.raw_pending=false;
            } else ++s.unmatched;
            break;
        case speedometer::FpuEvent::Abort:
            abort(s.timer);abort(s.callback);
            if(s.raw_pending){++s.raw_missing;s.raw_pending=false;}
            break;
        case speedometer::FpuEvent::Unmatched:++s.unmatched;break;
        }
    }
    void sample(const WindowSample& sample) {
        for(auto& s:site_) {
            if(s.timer.open && !s.timer.current.sample(sample))++invalid_samples_;
            if(s.callback.open && !s.callback.current.sample(sample))++invalid_samples_;
        }
    }
    bool dump() {
        if(dumped_)return true;
        FILE* f=fopen(path_.c_str(),"w");if(!f)return false;
        fprintf(f,"META\tformat\tfpu-timed-profile-v1\n");
        fprintf(f,"META\tclock\tpost_eval_33MHz_rising_edges\n");
        fprintf(f,"META\ttimer_bracket\tstart_trap_return_inclusive_to_stop_trap_call_exclusive\n");
        fprintf(f,"META\tcallback_bracket\tJSR_call_inclusive_to_return_exclusive\n");
        fprintf(f,"META\traw_microseconds\tA0_D0_at_timer_trap_returns\n");
        fprintf(f,"META\tsite_labels\tunknown_three_CODE3_sites\n");
        fprintf(f,"META\tinvalid_samples\t%llu\n",(unsigned long long)invalid_samples_);
        fprintf(f,"META\traw_cap\t%zu\nMETA\traw_dropped\t%llu\n",raw_cap_,(unsigned long long)raw_dropped_);
        fprintf(f,"META\tdiagnostic_dropped\t%llu\n",(unsigned long long)diagnostic_dropped_);
        fprintf(f,"SCHEMA\tTOTAL\tsite\tspan\tstatus\tclocks\tdispatches\tbg_samples\tblocking_decode\tgo_samples\tmrd_fill_overlap\tmrd_fill_unacked_overlap\n");
        fprintf(f,"SCHEMA\tHISTOGRAM\tkind\tsite\tspan\tstatus\tid\tclocks\n");
        fprintf(f,"SCHEMA\tRAW\tsite\tstart_A0D0\tstop_A0D0\tdelta_u64\tbackwards\tstart_return_cycle\tstop_return_cycle\n");
        fprintf(f,"SCHEMA\tDIAG\tsite\tcycle\tkind\treason\n");
        for(unsigned i=0;i<site_.size();++i) {
            const Site& s=site_[i];
            fprintf(f,"LIFECYCLE\t%u\tidentifies=%llu\tunmatched=%llu\traw_pairs=%llu\traw_missing=%llu\n",
                    i,(unsigned long long)s.identifies,(unsigned long long)s.unmatched,
                    (unsigned long long)s.raw_pairs,(unsigned long long)s.raw_missing);
            for(const auto pair : {std::pair<const char*,const Span&>{"timer",s.timer},
                                   {"callback",s.callback}}) {
                const Span& p=pair.second;
                fprintf(f,"SPAN\t%u\t%s\tstarts=%llu\tcomplete=%llu\taborted=%llu\topen=%u\n",
                        i,pair.first,(unsigned long long)p.starts,(unsigned long long)p.stops,
                        (unsigned long long)p.aborts,p.open);
                counters(f,i,pair.first,"complete",p.complete);
                counters(f,i,pair.first,"partial",p.partial);
            }
        }
        for(const Raw& r:raw_)
            fprintf(f,"RAW\t%u\t%llu\t%llu\t%llu\t%u\t%llu\t%llu\n",
                    r.site,(unsigned long long)r.start,(unsigned long long)r.stop,
                    (unsigned long long)(r.stop-r.start),r.stop<r.start,
                    (unsigned long long)r.start_cycle,(unsigned long long)r.stop_cycle);
        for(const Diagnostic& d:diagnostics_)
            fprintf(f,"DIAG\t%u\t%llu\t%s\t%s\n",d.site,(unsigned long long)d.cycle,
                    d.kind,d.reason.c_str());
        fclose(f);dumped_=true;return true;
    }
};

#endif
