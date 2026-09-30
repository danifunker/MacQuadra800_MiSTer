#include "m68k_dasm.h"
#include <fstream>
#include <vector>
#include <cstdio>
#include <cstdlib>
int main(int argc,char**argv){
 if(argc!=4)return 2;
 std::ifstream f(argv[1],std::ios::binary);std::vector<unsigned char>b((std::istreambuf_iterator<char>(f)),{});
 unsigned start=std::strtoul(argv[2],nullptr,0),end=std::strtoul(argv[3],nullptr,0);b.resize(b.size()+32);
 for(unsigned pc=start;pc<end;){char line[256];unsigned n=m68k_disassemble_raw(line,pc,b.data()+pc,b.data()+pc,M68K_CPU_TYPE_68040);
  const unsigned op=(unsigned(b[pc])<<8)|b[pc+1],ext=(unsigned(b[pc+2])<<8)|b[pc+3];
  if(op==0xf23c && (ext&0xe000)==0x4000){const unsigned bytes[]={4,4,12,12,2,8,2,12};n=4+bytes[(ext>>10)&7];}
  if(!n||pc+n>end)return 3;std::printf("%04x ",pc);for(unsigned i=0;i<n;i++)std::printf("%02x",b[pc+i]);std::printf("  %s\n",line);pc+=n;}
}
