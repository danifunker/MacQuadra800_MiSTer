#include "speedometer_observer.h"
#include <cassert>
#include <iostream>
#include <sstream>
using namespace speedometer;
static const uint32_t base=0x81234000; // deliberately not a physical-RAM address
static Registers regs() {Registers r;r.sr=0x2000;r.a[5]=0x92345000;r.a[6]=0xa1234000;return r;}
static uint32_t pc(uint32_t file,unsigned test) {return base+(file-0x62561)+(test?0x494:0);}
static void fetch(Observer& o,uint32_t addr,uint32_t data,uint8_t bytes=4,uint8_t fc=6,bool ce=true,bool error=false) {
 Bus b;b.addr=addr;b.data=data;b.bytes=bytes;b.fc=fc;b.request=b.ack=b.instruction=true;b.ce=ce;b.error=error;o.bus(b);
}
static void identify(Observer& o,unsigned test,Registers r,bool ce=true,bool error=false) {
 const uint32_t at=base+((test?0x65bb1:0x65729)-0x62561);
 fetch(o,at-12,0x3b7c0004,4,6,ce,error);
 fetch(o,at-8,0xbeaa3b7c,4,6,ce,error);
 fetch(o,at-4,test?0x00e2beac:0x0092beac,4,6,ce,error);
 o.dispatch(5,at-12,0x3b7c,r);
 Bus b;b.pc=at-12;b.addr=r.a[5]-0x4156;b.data=4;b.bytes=2;b.fc=5;
 b.request=b.ack=b.write=true;b.ce=ce;b.error=error;o.bus(b);
 o.dispatch(7,at-6,0x3b7c,r);
 b.pc=at-6;b.addr=r.a[5]-0x4154;b.data=test?0xe2:0x92;o.bus(b);
 o.dispatch(10,at,0x4eb9,r);
}
static void read(Observer& o,uint32_t addr,uint32_t data,uint8_t bytes,uint32_t owner) {
 Bus b;b.cycle=190;b.pc=owner;b.addr=addr;b.data=data;b.bytes=bytes;b.fc=5;b.request=b.ack=true;o.bus(b);
}
static void exercise(unsigned test,bool backwards) {
 std::ostringstream log;Observer o(log);Context c;c.mmu={0x8000,0x1000,0x2000,0,0,0,0};o.context(c,0);
 Registers r=regs();identify(o,test,r);assert(o.identities()==1);
 o.dispatch(20,pc(0x65747,test),0x4a2d,r);
 read(o,r.a[5]-0x36f2,1,1,pc(0x65747,test));
 r.a[0]=1;r.d[0]=0xfffffff0;o.dispatch(100,pc(0x65753,test),0x225f,r);
 fetch(o,pc(0x6576b,test)-4,test?0x3f3c000c:0x3f3c0006);
 o.dispatch(110,pc(0x6576b,test),0x4eb9,r);
 o.dispatch(160,pc(0x65771,test),0x4a2d,r);
 r.a[0]=backwards?1:2;r.d[0]=0x20;o.dispatch(180,pc(0x6577f,test),0x225f,r);
 o.dispatch(185,pc(0x65793,test),0x504f,r);
 r.d[4]=7;o.dispatch(186,pc(0x657a1,test),0xd8ae,r);
 const uint32_t elapsed=backwards?0x30:0x30;
 read(o,r.a[6]-4,elapsed>>16,2,pc(0x657a1,test));
 read(o,r.a[6]-2,elapsed&65535,2,pc(0x657a1,test));
 r.d[4]+=elapsed;o.dispatch(195,pc(0x657a5,test),0x5285,r);
 r.d[5]++;o.dispatch(196,pc(0x657a7,test),0x594f,r);
 r.d[0]=123;r.a[2]=122;o.dispatch(198,pc(0x657ad,test),0xb08a,r);
 o.dispatch(199,pc(0x657af,test),0x6590,r);
 const auto before=log.str().size();read(o,r.a[6]-4,99,4,0x1111);assert(log.str().size()==before);
 // Unload/reuse at the same logical base cannot rearm from old cached bytes
 // alone: a completed bracket requires fresh executed prefix writes.
 o.dispatch(200,base+((test?0x65bb1:0x65729)-0x62561),0x4eb9,r);
 o.dispatch(201,pc(0x65747,test),0x4a2d,r);
 assert(o.identities()==1 && log.str().size()==before);
 o.summary();const auto s=log.str();
 assert(s.find(test?"test=Sieve":"test=Queens")!=std::string::npos);
 assert(s.find("elapsed_read_valid=1")!=std::string::npos);
 assert(s.find("sum_matches=1")!=std::string::npos);
 assert(s.find(backwards?"backwards=1":"delta_u64=48 backwards=0")!=std::string::npos);
 // Low32 alone cannot distinguish a high-word error: retain the full raw
 // values and backwards flag instead of treating low32 agreement as proof.
 assert(s.find("raw_low32_matches=1")!=std::string::npos);
 std::cout<<s;
}
int main() {
 exercise(0,false);exercise(1,false);exercise(1,true);
 {
  std::ostringstream log;Observer o(log,4);Context c;
  for(unsigned i=0;i<1000;i++){c.mmu[1]=i;o.context(c,i);}
  assert(!o.bounded());identify(o,0,regs());assert(o.identities()==1&&!o.bounded());
 }
 {
  std::ostringstream log;Observer o(log);Registers r=regs();
  identify(o,0,r,false);identify(o,0,r,true,true);assert(o.identities()==0);
  identify(o,0,r);assert(o.identities()==1);
  Context c;c.mmu[0]=0x8000;o.context(c,30);
  o.dispatch(31,base+(0x65729-0x62561),0x4eb9,r);assert(o.identities()==1);
  identify(o,0,r);assert(o.identities()==2);
  o.invalidate(35,"TEST_SAME_ROOT_PTE_REMAP");
  o.dispatch(36,base+(0x65729-0x62561),0x4eb9,r);assert(o.identities()==2);
  o.reset(true);o.reset(false);o.dispatch(40,base+(0x65729-0x62561),0x4eb9,r);assert(o.identities()==2);
 }
 {
  std::ostringstream log;Observer o(log,3);auto r=regs();identify(o,1,r);
  o.dispatch(20,pc(0x65747,1),0x4a2d,r);o.dispatch(30,pc(0x6575b,1),0x4eb9,r);
  assert(o.bounded());auto n=log.str().size();o.dispatch(40,pc(0x6577f,1),0x225f,r);assert(log.str().size()==n);
 }
 {
  std::ostringstream log;Observer o(log);auto r=regs();identify(o,0,r);
  o.dispatch(20,pc(0x65747,0),0x4a2d,r);o.dispatch(30,pc(0x6575b,0),0x4eb9,r);
  o.dispatch(40,0x40801234,0xa058,r);o.dispatch(41,0x40802345,0xa05a,r);
  r.d[0]=456;o.dispatch(50,pc(0x6579d,0),0x2d40,r);
  assert(log.str().find("TIME_MANAGER_TRAP")!=std::string::npos);
  assert(log.str().find("RAW_DELTA")==std::string::npos);
  o.dispatch(60,pc(0x657a1,0),0xffff,r);assert(log.str().find("IDENTITY_LOST")!=std::string::npos);
 }
 {
  Registers r=regs();apply_pending(r,true,0,123,false,0,0);assert(r.d[0]==123&&r.pending);
  apply_pending(r,true,8,456,false,0,0);assert(r.a[0]==456);
  for(unsigned sp=0;sp<3;sp++) {
   r.sr=sp==0?0:sp==1?0x2000:0x3000;
   apply_pending(r,true,15,100,true,sp,200);assert(r.a[7]==200);
   apply_pending(r,true,15,300,true,(sp+1)%3,400);assert(r.a[7]==300);
  }
 }
 std::cout<<"PASS synthetic runtime relocation, raw carry/backwards, MMU context invalidation, fault/CE exclusion, split elapsed read, aggregate, fallback, bounds, pending RF and SP banks\n";
}
