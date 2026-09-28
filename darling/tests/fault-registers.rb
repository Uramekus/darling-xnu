# Test the production register-formatting expression with inaccessible saved
# stack/frame addresses. Does not exercise signal forwarding or the RPC logger.
require 'tmpdir'
path=File.expand_path('../src/libsystem_kernel/emulation/src/linux_premigration/signal/sigexc.c',__dir__)
call=File.read(path)[/kern_printf\("sigexc: ARM64 registers.*?;/m]
abort 'register diagnostic not found' unless call
program=<<~C
  #include <assert.h>
  #include <stdint.h>
  #include <stdio.h>
  #include <string.h>
  int main(void) {
    struct { struct { struct { uint64_t regs[31],sp; } gregs; } uc_mcontext; } context={0}, *ctxt=&context;
    char buffer[512];
    #define kern_printf(...) snprintf(buffer,sizeof buffer,__VA_ARGS__)
    for(int i=0;i<31;++i) context.uc_mcontext.gregs.regs[i]=UINT64_MAX;
    context.uc_mcontext.gregs.regs[29]=1; /* invalid FP: must not dereference */
    context.uc_mcontext.gregs.sp=1;
    int length=#{call}
    assert(length>0 && (size_t)length<sizeof buffer);
    assert(strstr(buffer,"FP=0x1 "));
    assert(strstr(buffer,"LR=0xffffffffffffffff "));
    assert(strstr(buffer,"x19=0xffffffffffffffff "));
    assert(strstr(buffer,"x22=0xffffffffffffffff\\n"));
    puts("PASS: saved registers formatted without frame dereference; fits 512-byte logger");
  }
C
Dir.mktmpdir('fault-registers') do |dir|
  input=File.join(dir,'test.c'); output=File.join(dir,'test')
  File.write(input,program)
  abort 'compile failed' unless system('clang','-Wall','-Wextra','-fsanitize=address,undefined',input,'-o',output)
  abort 'test failed' unless system(output,rlimit_core:0)
end
