# Preserved Titan Ridge research

`0005-titan-ridge-type3-power-sequence.patch` is preserved byte-for-byte from
the former patch stack. It is **not part of the active Falcon build** and has
not been rebased, compiled or tested with that configuration.

The earlier stack recorded six `pm_test=platform` cycles and one 123.7-second
s2idle with both USB-C ports empty, with no Titan Ridge PM failures and both
controllers later reaching D3cold. Attached-device suspend remained untested.
Those historical results are not Falcon validation.

The patch came from a five-patch stack on the older T2 base. Its references to
`mbp161_tb_bypass` describe that stack's PCI bypass; that parameter is not
provided by the active Falcon patch. Do not use its historical fallback
arguments or assume this is a supported standalone add-on.

The sequence and earlier verification are available in the
[previous kernel notes](https://github.com/yuters/mbp161-hybrid-graphics/blob/e77b03f/kernel/README.md).
Preserving the investigation avoids discarding independent USB-C work while
removing it from instructions that would imply it is part of the tested fix.
