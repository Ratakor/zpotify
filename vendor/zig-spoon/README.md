# zig-spoon

zig-spoon official repository is [here](https://git.sr.ht/~leon_plickat/zig-spoon).
This is a modified version of zig-spoon based on commit [ecaa2f9c](https://git.sr.ht/~leon_plickat/zig-spoon/commit/ecaa2f9cf6c8680fa75adc4b5b791d4d57bd246a)
for [zpotify](https://github.com/ratakor/zpotify).

---

zig-spoon is a zig library offering a simple, low-level and allocation free
abstraction for creating TUI programs. zig-spoon takes care of wrangling the
terminal, but unlike other TUI libraries it does not get in the way when you
want to render the interface.

zig-spoon supports the kitty keyboard protocol.

The text attribute code can be used independently, so zig-spoon is also useful
for non-TUI terminal programs that still want fancy text.

```
    _
  /   \
 |     |
  \   /
   | |
   | |
   | |
   | |
   (_)
```


## Read this before using zig-spoon!

I am happy you are interested in this project and I hope it will serve you well.
However before you continue, I'd like to quickly explain and mention a few
things, that will make working with zig-spoon clearer. You can consider this to
be part of the documentation, if you like.

Despite being a modern library written in a modern language, zig-spoon will
always be held back by the countless legacy interfaces and hacks it tries to
abstract away from you. This is inevitable. While you shouldn't need to worry
about this too much, there are a few things you probably want to know.

Unless the terminal your zig-spoon application is running in supports the kitty
keyboard protocol, keyboard input has certain limitations. It is impossible to
differentiate between `M-a` or the user simply pressing `escape` and `a` in
sequence fast enough (`a` is an example, this holds for all keys). It is
impossible to differentiate `C-m`, `C-j` and `enter`, so to err on the side of
caution, zig-spoon will always assume `enter` is the intended key press.
Any non-ascii characters may behave in an unexpected manner, depending on the
terminal emulator. The super modifier is only supported when the kitty keyboard
protocol is used.

If the kitty keyboard protocol is available, zig-spoon will use its lowest mode.
This way zig-spoon can use the same input system for both legacy and kitty
inputs, which is nicer for both library and application developers. Additional
information that can be added to the input system without compromising its
support for legacy inputs will be implemented where possible / feasible / useful.
While the higher kitty keyboard modes offer even more information about inputs,
they are generally not needed for the average terminal application. The lowest
mode already fixes all major input annoyances that were outlined in the previous
paragraph. If you do need the extra information, you can easiely replace
zig-spoons input parser with your own custom one.

The traditional 16 terminal colours may differ between background versus
foreground and normal versus bold text. So `.{ .fg = .red }` and
`.{ .bg = .red, .reverse = true }` may look different, despite describing the
same attributes in theory. Also the colours from the 256-colours mode can differ
drastically between terminal emulators. If you value acuarate colours, you
probably should use the RGB-colour mode.

And certainly the saddest caveat: Not all terminal emulators support blinking
text.

If you face any issues or unexpected oddities, please contact me so that we can
figure out a way around them.


## API Stability

**API stability is not guaranteed.**

If I realize that any API I designed does not fulfill its purpose in a sane
manner, it will be improved or completely replaced. I do not guarantee backward
or forward compatability. In fact, I can likely promise their certain absence.

The purpose of zig-spoon is to work around outdated and outright broken legacy
APIs so that the application developers can focus on other things. As such I
believe that allowing zig-spoons API to stagnate and rot in a similar way would
just be silly, literally defeating the purpose of using this library at all.

This means that you can can get involved in designing and improving the API.
So if you have any thoughts on it, feel free to contact me.


## License

zig-spoon is licensed under the GPL version 3 (no later).

Yes, that means that any project using zig-spoon - although not necessarily
all code - will also be licensed under the GPLv3. This should not be a problem
for any honest FOSS project.

While I recognize that licensing a  library under the GPL is unusual and poses
restrictions on users of the library, I consider this choice necessary to ensure
that all my code always remains Free Software and therefore always remains of
most use to end users. I write software for people, not for companies. As such,
I do not wish any of it being used as free labour for some proprietary project
by a company wanting to improve their profit margins.
Thank you for understanding.
