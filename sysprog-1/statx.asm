section	.data
    newline db 10
    ASCII_buffer times 20 db 0     ; buffer to store ASCII representation of the number

    AT_FDCWD dq -100
    AT_SYMLINK_NOFOLLOW dq 0x100
    STATX_UID_or_GID dq 0x00000018
    STATX_SIZE dq 0x00000200
    STATX_MODE dq 0x00000002

    S_IRUSR dw 0x0100
    S_IWUSR dw 0x0080
    S_IXUSR dw 0x0040
    S_IRGRP dw 0x0020
    S_IWGRP dw 0x0010
    S_IXGRP dw 0x0008
    S_IROTH dw 0x0004
    S_IWOTH dw 0x0002
    S_IXOTH dw 0x0001

    fmt_UID db "UID: "
    fmt_UID_length equ $ - fmt_UID
    fmt_GID db ", GID: "
    fmt_GID_length equ $ - fmt_GID
    fmt_size db "Size: "
    fmt_size_length equ $ - fmt_size

    permissions db "---------"
    permissions_length equ $ - permissions
    
    ; struct statx
    stx_mask dd 0
    stx_blksize dd 0
    stx_attributes dq 0
    stx_nlink dd 0
    stx_uid dd 0
    stx_gid dd 0
    stx_mode dw 0
    __spare0 dw 0
    stx_ino dq 0
    stx_size dq 0
    stx_blocks dq 0
    stx_attributes_mask dq 0

section	.text
    global _start
	
_start:
    ; sys_write with strlen
    ; rsp = argc, argv[1] = argc + 8 bytes sizeof(int) + 8 bytes sizeof(char *)
    ; mov	rdi, [rsp + 8 + 8]  ; argv[0] program name, argv[1] first argument
    ; call strlen
    ; mov	rdx, rax
    ; mov	rax, 1
    ; mov	rsi, rdi
    ; mov	rdi, 1
    ; syscall

    ; call println

    ; statx
    mov	rax, 332
    mov	rdi, [AT_FDCWD]
    mov	rsi, [rsp + 8 + 8]
    mov	rdx, [AT_SYMLINK_NOFOLLOW]
    mov r10, [STATX_UID_or_GID]
    mov r8, stx_mask    ; &buf
    syscall

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_UID
    mov	rdx, fmt_UID_length
    syscall

    mov eax, [stx_uid]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_GID
    mov	rdx, fmt_GID_length
    syscall

    mov eax, [stx_gid]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; statx
    mov	rax, 332
    mov	rdi, [AT_FDCWD]
    mov	rsi, [rsp + 8 + 8]
    mov	rdx, [AT_SYMLINK_NOFOLLOW]
    mov r10, [STATX_SIZE]
    mov r8, stx_mask    ; &buf
    syscall

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, fmt_size
    mov	rdx, fmt_size_length
    syscall

    mov rax, [stx_size]
    call itoa   ; number in rax, buffer in rsi, uses rcx, rdx

    ; sys_write int with strlen
    mov	rdi, rsi
    call strlen
    mov	rdx, rax
    mov	rax, 1
    mov	rdi, 1
    syscall

    call println

    ; statx
    mov	rax, 332
    mov	rdi, [AT_FDCWD]
    mov	rsi, [rsp + 8 + 8]
    mov	rdx, [AT_SYMLINK_NOFOLLOW]
    mov r10, [STATX_MODE]
    mov r8, stx_mask    ; &buf
    syscall

    call printPermissions

    ; sys_write
    mov	rax, 1
    mov	rdi, 1
    mov	rsi, permissions
    mov	rdx, permissions_length
    syscall

    call println

    ; sys_exit
    mov	rax, 60
    mov	rdi, 0
    syscall

printPermissions:
    mov ax, [stx_mode]
    mov rsi, permissions

    test rax, [S_IRUSR]
    jz .skip_user_read
    mov byte [rsi + 0], 'r'
.skip_user_read:
    test rax, [S_IWUSR]
    jz .skip_user_write
    mov byte [rsi + 1], 'w'
.skip_user_write:
    test rax, [S_IXUSR]
    jz .skip_user_exec
    mov byte [rsi + 2], 'x'
.skip_user_exec:
    test rax, [S_IRGRP]
    jz .skip_group_read
    mov byte [rsi + 3], 'r'
.skip_group_read:
    test rax, [S_IWGRP]
    jz .skip_group_write
    mov byte [rsi + 4], 'w'
.skip_group_write:
    test rax, [S_IXGRP]
    jz .skip_group_exec
    mov byte [rsi + 5], 'x'
.skip_group_exec:
    test rax, [S_IROTH]
    jz .skip_other_read
    mov byte [rsi + 6], 'r'
.skip_other_read:
    test rax, [S_IWOTH]
    jz .skip_other_write
    mov byte [rsi + 7], 'w'
.skip_other_write:
    test rax, [S_IXOTH]
    jz .skip_other_exec
    mov byte [rsi + 8], 'x'
.skip_other_exec:
    ret

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

; integer in rax, return value (const char *) in rsi
itoa:
    ; Convert the number to its ASCII representation
    mov rsi, ASCII_buffer + 19  ; rsi is last element in buffer
    mov byte [rsi], 0   ; null terminate the buffer
    dec rsi ; move pointer to the previous byte
    mov rcx, 10 ; set divisor, rax % 10
    .mod10:
        xor rdx, rdx    ; zeroed remainder
        div rcx ; divide rax by 10; result goes in rax, remainder in rdx
        add dl, '0' ; convert remainder to ASCII
        mov [rsi], dl   ; store ASCII character in the buffer
        dec rsi ; move pointer to the previous byte
        test rax, rax ; if rax != 0
        jnz .mod10  ; repeat until quotient is zero
    inc rsi ; after "dec rsi" move pointer to the next byte, last stored ASCII character in the buffer
    ret
