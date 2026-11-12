; keyecho: the Amiga console in raw mode, step 1 of p8vi's Amiga port.
; Each key shows the bytes the console sends for it, in hex, and the
; ASCII ones as characters; s sends the window status request (CSI 0 SPACE
; q), whose answer shows the same way; q quits, with the console back in
; its normal (cooked) mode.  Window resizes are reported as they happen:
; CSI 12 { asks the console for raw events of class 12 (a window resized),
; which come in with the keys as CSI 12 ; ... | (CSI 12 } before quitting
; stops them).
;
; Kickstart 1.3 and later: raw mode is the ACTION_SCREEN_MODE packet sent
; to the console's handler (dos.SetMode is Kickstart 2.0), keys are
; dos.WaitForChar and dos.Read.  Numbers are formatted with conv (exec's
; RawDoFmt): txt's own print_ub and the like need Kickstart 2.0 (VPrintf).
;
;   prog8c-llvm -target amiga500 -out build tests/amiga/keyecho.p8
;   copperline --run build/keyecho --model A500     (or -emu)

%import textio
%import conv
%import dos
%import exec

main {
    ubyte[16] got           ; the bytes of a key (static: dos.Read gets its address)

    sub start() {
        pointer con = dos.Input()
        if con == 0 or dos.IsInteractive(con) == 0 {
            txt.print("keyecho: not in a console window\n")
            return
        }
        if not screen_mode(con, true) {
            txt.print("keyecho: no raw mode\n")
            return
        }
        txt.print("keys show their bytes in hex; s: the window's size; q: quit\n")
        txt.print("\x9b12{")       ; (the window's resizes reported)
        ubyte n
        ubyte i
        repeat {
            ; (WaitForChar: a key within the time, in microseconds)
            if dos.WaitForChar(con, 5000000) == 0 {
                txt.print("(no key for 5 seconds)\n")
                continue
            }
            ; the bytes that come together: one key, or a sequence
            n = 0
            while n < len(got) and dos.Read(con, &got + n, 1) == 1 {
                n++
                if dos.WaitForChar(con, 50000) == 0
                    break
            }
            for i in 0 to n - 1 {
                txt.print(conv.str_ubhex(got[i]))
                txt.print(" ")
            }
            txt.print(" ")
            for i in 0 to n - 1 {
                if got[i] >= 32 and got[i] < 127
                    txt.chrout(got[i])
                else
                    txt.chrout('.')
            }
            txt.print("\n")
            if n == 1 and got[0] == 'q'
                break
            if n == 1 and got[0] == 's'
                txt.print("\x9b0 q")
        }
        txt.print("\x9b12}")       ; (no more resize reports)
        void screen_mode(con, false)
        txt.print("keyecho: cooked mode again\n")
    }

    ; a console file handle in raw mode (no line editing, no echo: each key
    ; as it comes) or cooked mode.  false if its handler doesn't take the
    ; packet (not a console).  The packet goes to the handler's port (the
    ; FileHandle's Type), the reply to the process's own port (pr_MsgPort,
    ; as AmigaDOS does it).
    sub screen_mode(pointer con, bool raw) -> bool {
        ^^dos.FileHandle fh = ((con as long) << 2) as ^^dos.FileHandle    ; (a BPTR)
        ^^exec.MsgPort handler = fh.Type
        if handler == 0
            return false
        ^^exec.MsgPort reply = ((exec.FindTask(0) as long) + 92) as ^^exec.MsgPort   ; pr_MsgPort
        ; (a StandardPacket must be longword aligned: AllocMem's are)
        ^^dos.StandardPacket pkt = exec.AllocMem(sizeof(dos.StandardPacket) as long, exec.MEMF_PUBLIC | exec.MEMF_CLEAR) as ^^dos.StandardPacket
        if pkt == 0
            return false
        pokel((pkt as long) + 10, (pkt as long) + 20)   ; the message's name (ln_Name): its DosPacket
        pkt.Link = pkt as ^^exec.Message                 ; the packet's message
        pkt.Port = reply
        pkt.DosPacket_Type = dos.ACTION_SCREEN_MODE
        pkt.Arg1 = 0
        if raw
            pkt.Arg1 = dos.DOSTRUE
        exec.PutMsg(handler, pkt as ^^exec.Message)
        void exec.WaitPort(reply)
        void exec.GetMsg(reply)
        bool ok = pkt.Res1 != 0
        exec.FreeMem(pkt as pointer, sizeof(dos.StandardPacket) as long)
        return ok
    }
}
