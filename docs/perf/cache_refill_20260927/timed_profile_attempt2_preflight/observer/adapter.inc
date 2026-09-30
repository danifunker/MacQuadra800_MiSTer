// Simulation-only adapter: no RTL/public attribute changes required.
#include "speedometer_observer.h"
#include <fstream>
#include <memory>
static std::string speedometer_path;
static uint64_t speedometer_limit=512;
static std::ofstream speedometer_file;
static std::unique_ptr<speedometer::Observer> speedometer_observer;
#define SPEED_CORE(field) SIMEMU->__PVT__machine__DOT__cpu__DOT__core__DOT__##field
#define SPEED_CPU(field) SIMEMU->__PVT__machine__DOT__cpu__DOT__##field
static speedometer::Context speedometer_context() {
    speedometer::Context c;
    c.mmu={SPEED_CORE(tc),SPEED_CORE(urp),SPEED_CORE(srp),SPEED_CORE(itt0),
           SPEED_CORE(itt1),SPEED_CORE(dtt0),SPEED_CORE(dtt1)};
    return c;
}
static uint8_t speedometer_before_state=255;
static bool speedometer_pipe_admit=false,speedometer_pipe_rf_owner=false;
static uint32_t speedometer_pipe_pc=0;
static uint16_t speedometer_pipe_opcode=0;
static void speedometer_before_eval() {
    if(!speedometer_observer) return;
    speedometer_observer->reset(VERTOPINTERN->reset);
    if(VERTOPINTERN->reset) return;
    speedometer_before_state=SPEED_CORE(state);
    speedometer_pipe_admit=SPEED_CORE(pipe_input)&&SPEED_CORE(pipe_ready);
    speedometer_pipe_rf_owner=SPEED_CORE(pipe_rf_owner);
    speedometer_pipe_pc=speedometer_pipe_rf_owner?SPEED_CORE(pc):SPEED_CORE(pc_i);
    speedometer_pipe_opcode=speedometer_pipe_rf_owner?SPEED_CORE(epf_data)[SPEED_CORE(epf_head)]:SPEED_CORE(ir);
    speedometer_observer->context(speedometer_context(),main_time/2);
    static bool invalidating=false;
    const bool flush=SPEED_CPU(pf_req)||SPEED_CPU(cinv_req);
    if(flush && !invalidating)speedometer_observer->invalidate(main_time/2,"PFLUSH_OR_CINV");
    invalidating=flush;
    speedometer::Bus b;
    b.cycle=main_time/2;b.pc=SPEED_CORE(pc_i);
    b.request=SPEED_CPU(mem_req);b.ack=SPEED_CPU(mem_ack);
    b.error=SPEED_CPU(mem_flt)||(SPEED_CPU(mem_instr)?SPEED_CPU(ifr_berr):SPEED_CPU(core_berr));b.instruction=SPEED_CPU(mem_instr);
    b.write=SPEED_CPU(mem_write);b.addr=SPEED_CPU(mem_addr);
    b.fc=SPEED_CPU(mem_fc);b.bytes=uint8_t(1u<<SPEED_CPU(mem_size));
    b.data=b.write?SPEED_CPU(core_wdata):SPEED_CPU(mm_rdata);   // P171: the wrapper aliases mem_wdata to core_wdata and mem_rdata to the cache's mm_rdata
    // sim.v ties the machine CE to 1. This adapter must be changed if that
    // integration changes; the standalone observer nevertheless tests CE=0.
    b.ce=true;
    speedometer_observer->bus(b);
}
static void speedometer_after_eval(bool dispatch) {
    if(!speedometer_observer) return;
    speedometer_observer->context(speedometer_context(),main_time/2);
    if(!dispatch) return;
    speedometer::Registers r;
    r.sr=SPEED_CORE(sr);
    for(unsigned i=0;i<15;i++) {
        uint32_t value=(SPEED_CORE(regfile__DOT__rf_written)&(1u<<i)) ?
            SPEED_CORE(regfile__DOT__bank_a)[i] : 0;
        if(SPEED_CORE(regfile__DOT__pend_we) && SPEED_CORE(regfile__DOT__pend_waddr)==i)
            value=SPEED_CORE(regfile__DOT__pend_wdata);
        if(i<8)r.d[i]=value; else r.a[i-8]=value;
    }
    const unsigned sp=!(r.sr&0x2000)?0:((r.sr&0x1000)?2:1);
    r.a[7]=sp==0?SPEED_CORE(regfile__DOT__usp):sp==1?SPEED_CORE(regfile__DOT__isp):SPEED_CORE(regfile__DOT__msp);
    // A retirement can dispatch the next opcode one edge before the RF
    // commits its registered write. Report that pending write explicitly and
    // overlay it, matching the core's existing operand-forwarding boundary.
    speedometer::apply_pending(r,SPEED_CORE(rf_we),SPEED_CORE(rf_waddr),SPEED_CORE(rf_wdata),
                               SPEED_CORE(aux_we),SPEED_CORE(aux_sel),SPEED_CORE(aux_wdata));
    const bool secondary=speedometer_pipe_admit&&speedometer_pipe_rf_owner;
    // Secondary admissions lack an architectural register snapshot. All FPU
    // timer/callback opcodes are unsupported; initial MOVEQ return recognition
    // follows an unsupported RTS and has its own primary dispatch.
    speedometer_observer->dispatch(main_time/2,
        secondary?speedometer_pipe_pc:SPEED_CORE(pc_i),
        secondary?speedometer_pipe_opcode:SPEED_CORE(ir),r,SPEED_CORE(state),
        speedometer_before_state,speedometer_pipe_admit,speedometer_pipe_rf_owner,speedometer_pipe_pc,!secondary);
    // Fail before a long workload if the selected fetch channel is not observed.
    // This checks only nonzero sanity, not complete prefetch/BRF visibility.
    if(speedometer_observer->dispatches()==10000 &&
       (!speedometer_observer->instruction_acks()||!speedometer_observer->known_dispatches())) {
        speedometer_observer->summary();
        fprintf(stderr,"[OBSERVER] adapter sanity failed after 10000 dispatches\n");
        std::exit(3);
    }
}
#undef SPEED_CORE
#undef SPEED_CPU
