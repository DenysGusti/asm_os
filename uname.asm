section	.data
    newline db 10

    fmt_hostname db "Hostname: "
    fmt_hostname_length equ $ - fmt_hostname
    fmt_os db "OS: "
    fmt_os_length equ $ - fmt_os
    fmt_version db "Version: "
    fmt_version_length equ $ - fmt_version
    fmt_release db "Release: "
    fmt_release_length equ $ - fmt_release

    ; struct utsname
    sysname db 65 dup(0)
    nodename db 65 dup(0)
    release db 65 dup(0)
    version db 65 dup(0)
    machine db 65 dup(0)

section	.text
    global _start
	
_start:
    ; sys_uname
    mov	rax, 63
    mov	rdi, sysname    ; &buf
    syscall

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_hostname
    mov	rdx, fmt_hostname_length
    syscall

    ; sys_write with strlen
    mov	rdi, nodename
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall
    
    call println

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_os
    mov	rdx, fmt_os_length
    syscall

    ; sys_write with strlen
    mov	rdi, sysname
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_version
    mov	rdx, fmt_version_length
    syscall

    ; sys_write with strlen
    mov	rdi, version
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_release
    mov	rdx, fmt_release_length
    syscall

    ; sys_write with strlen
    mov	rdi, release
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rsi, rdi
    mov	rdi, 1
    syscall

    call println

    ; sys_exit
    mov	rax, 60
    mov	rdi, 0
    syscall

println:
    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, newline
    mov	rdx, 1
    syscall
    ret

; const char * in rdi, return value (int) in rax
strlen:
    xor rax, rax    ; string length in rax, zeroed
    .find_null_byte:
        cmp byte [rdi + rax], 0 ; rdi[rax] == '\0', byte size operands
        je .end ; break if true
        inc rax ; ++rax
        jmp .find_null_byte
    .end:
        ret
