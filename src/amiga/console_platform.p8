%import dos
%import exec

;
; the console for src/cpm/textio.p8 in the Amiga build: the CLI window
; p8vi runs in (console.device, an ANSI terminal), through dos.library.
; Kickstart 1.3 and later.
;
; start() puts the window in raw mode (no line editing, no echo: each key
; as it comes), stop() back in the normal (cooked) mode.  On 1.3 that's
; the ACTION_SCREEN_MODE packet to the console's handler (dos.SetMode is
; 2.0); tests/amiga/keyecho.p8 shows the keys' codes.  Output is kept in
; a buffer and written when the program waits for a key (one dos.Write
; per character would be slow).  The cursor and function keys come as
; CSI ($9B) sequences: platform.get_key has txt.escape_key read them.
;
; The window's resizes: start() asks the console for raw events of class 12
; (CSI 12 {), so a resize puts CSI 12 ; ... | in with the keys (once, when
; the drag ends; Kickstart 1.3 too).  Reading a CSI sequence whole, the
; console takes that report out: resized, and no key (0, as the host's
; console does), and the window's size is asked again (size()).  Other
; sequences are passed on as they came, a byte at a time.
;
console {
    ; the largest screen txt keeps (its buffers' size): a window up to
    ; this is used, a bigger one shows this much
    const ubyte MAX_WIDTH = 160
    const ubyte MAX_HEIGHT = 80
    ; the console keeps keys typed while the screen is sent: txt needn't
    ; ask for them (each ask is a packet to the console)
    const bool KEEPS_KEYS = true

    pointer in_fh           ; Input(), Output(): the window
    pointer out_fh
    ubyte[1] in_byte        ; (static: dos.Read gets its address)
    ubyte[200] out_buf
    ubyte out_len
    bool stopped            ; after stop(): output is written as it comes

    ; a resize report came: wait() or poll() returned 0 for it (platform)
    bool resized
    ; a CSI sequence read whole that wasn't a report: its bytes, given out
    ; one by one before anything new is read.  (a resize report is about
    ; 30 bytes, with its time stamp; a longer sequence is read to its end
    ; and dropped)
    ubyte[48] seq
    ubyte seq_len
    ubyte seq_pos

    ; the window in raw mode; false if p8vi isn't in a console window
    sub start() -> bool {
        in_fh = dos.Input()
        out_fh = dos.Output()
        if in_fh == 0 or out_fh == 0 or dos.IsInteractive(in_fh) == 0
            return false
        if not screen_mode(true)
            return false
        ; (the window's resizes reported: raw events of class 12)
        out($9b)
        out('1')
        out('2')
        out('{')
        return true
    }

    ; what's left written, and the window in its normal mode again.  What
    ; comes after (the editor clears the screen as it quits, leaving the
    ; cursor at the top left for the CLI's prompt) is written at once:
    ; nothing writes the buffer once the program ends
    sub stop() {
        ; (no more resize reports, in the CLI either)
        out($9b)
        out('1')
        out('2')
        out('}')
        flush()
        void screen_mode(false)
        stopped = true
    }

    sub out(ubyte char) {
        out_buf[out_len] = char
        out_len++
        if out_len == len(out_buf) or stopped
            flush()
    }

    sub flush() {
        if out_len != 0 {
            void dos.Write(out_fh, &out_buf, out_len)
            out_len = 0
        }
    }

    ; a key typed, 0 for none (or a resize report: resized)
    sub poll() -> ubyte {
        if seq_pos == seq_len and dos.WaitForChar(in_fh, 0) == 0
            return 0
        return next_key()
    }

    ; a key, waiting for it (the output written first); 0 if the input
    ; ended, or for a resize report (resized)
    sub wait() -> ubyte {
        flush()
        ubyte k
        repeat {
            k = next_key()
            ; (0 for a sequence dropped: wait on)
            if k != 0 or resized or ended
                return k
        }
    }

    ; the next key: the rest of a sequence read before, or one read now.
    ; A CSI is read with the rest of its sequence (it comes all at once):
    ; a resize report is taken out, anything else is given out byte by byte
    sub next_key() -> ubyte {
        if seq_pos != seq_len {
            seq_pos++
            return seq[seq_pos - 1]
        }
        ubyte k = read_byte()
        if k != $9b
            return k
        ; the sequence: parameters and intermediate bytes up to the final one
        seq[0] = k
        seq_len = 1
        repeat {
            if dos.WaitForChar(in_fh, 50000) == 0
                break
            k = read_byte()
            if seq_len < len(seq) {
                seq[seq_len] = k
                seq_len++
            }
            if k >= $40
                break
        }
        if seq_len == len(seq) and seq[len(seq) - 1] != k {
            ; (too long: dropped, as txt.escape_key drops what it doesn't know)
            seq_len = 0
            seq_pos = 0
            return 0
        }
        ; CSI 12 ; ... | : the window was resized
        if seq_len > 4 and seq[1] == '1' and seq[2] == '2' and seq[3] == ';' and k == '|' {
            seq_len = 0
            seq_pos = 0
            resized = true
            return 0
        }
        seq_pos = 1
        return seq[0]
    }

    bool ended              ; the input ended (or failed)
    sub read_byte() -> ubyte {
        if dos.Read(in_fh, &in_byte, 1) != 1 {
            ended = true
            return 0
        }
        return in_byte[0]
    }

    ; the window's size: columns (lsb) and rows (msb), 0 if it doesn't
    ; say.  The window status request, CSI 0 SPACE q, is answered with
    ; CSI 1 ; 1 ; rows ; cols SPACE r (as keys; raw mode): at the start,
    ; and after a resize report (keys typed in between would be taken for
    ; the answer).
    sub size() -> uword {
        out($9b)
        out('0')
        out(' ')
        out('q')
        flush()
        ubyte k = timed_byte()
        if k == 27 {
            if timed_byte() != '['
                return 0
        } else if k != $9b
            return 0
        ; 1 ; 1 ; rows ; cols
        uword n = 0
        uword rows = 0
        ubyte fields = 0
        repeat {
            k = timed_byte()
            if k >= '0' and k <= '9' {
                n = n * 10 + k - '0'
                if n > 999
                    return 0
            } else if k == ';' {
                fields++
                if fields == 3
                    rows = n
                n = 0
            } else
                break
        }
        ; (the end: SPACE r)
        if k != ' ' or timed_byte() != 'r' or fields != 3 or rows == 0 or n == 0
            return 0
        return mkword(min(rows, 255) as ubyte, min(n, 255) as ubyte)
    }

    ; (size) a byte of the answer, 0 if none came in half a second
    sub timed_byte() -> ubyte {
        if dos.WaitForChar(in_fh, 500000) == 0
            return 0
        return read_byte()
    }

    ; the window in raw mode (no line editing, no echo: each key as it
    ; comes) or cooked mode.  false if its handler doesn't take the packet.
    ; The packet goes to the handler's port (the FileHandle's Type), the
    ; reply to the process's own port (pr_MsgPort, as AmigaDOS does it).
    sub screen_mode(bool raw) -> bool {
        ^^dos.FileHandle fh = ((in_fh as long) << 2) as ^^dos.FileHandle    ; (a BPTR)
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
