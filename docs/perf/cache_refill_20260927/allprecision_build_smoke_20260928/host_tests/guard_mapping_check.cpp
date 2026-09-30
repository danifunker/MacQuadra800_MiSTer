#include "Vemu_emu.h"
#include "sim_fpu_guard_profile.h"
extern Vemu_emu* model;
struct ResetPort {bool reset;};
extern ResetPort reset_port;
#define SIMEMU model
#define VERTOPINTERN (&reset_port)
static SimFpuGuardEdge bracket_fpu_edge;
static void fpu_guard_before_eval() {
    auto* e=SIMEMU;
    SimFpuGuardEdge s;
    s.nreset=!VERTOPINTERN->reset; // sim.v machine nreset=~reset
    s.ce=true; // sim.v machine ce=1
    s.req=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_req;
    s.opclass=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_class;
    s.format=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_fmt;
    s.opmode=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_opm;
    s.restore_unimp=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_frestore_unimp;
    s.restore_resume=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_frestore_resume;
    s.state_unimp=e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_fstate_unimp;
    s.pc=e->__PVT__machine__DOT__cpu__DOT__core__DOT__pc_i;
    s.fpcr=e->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__fpcr;
    s.fst=e->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__fst;
    s.state_e1=e->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__fstate_e1;
    s.state_resig=e->__PVT__machine__DOT__cpu__DOT__core__DOT__g_fpu__DOT__fpu__DOT__fstate_resig;
    s.exponent=(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpb[2]>>23)&255;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_crwe)<<0;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_fmwe)<<1;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_bsun)<<2;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_rst)<<3;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_frestore_idle)<<4;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_frestore_unimp)<<5;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_fsave_ack)<<6;
    s.sideports|=uint8_t(e->__PVT__machine__DOT__cpu__DOT__core__DOT__fpu_pendcap)<<7;
    bracket_fpu_edge=s;
}
