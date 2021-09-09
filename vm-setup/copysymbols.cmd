@ECHO OFF
set branch=rs_onecore
set build=21321.1000.210219-1428
ROBOCOPY.exe \\winbuilds\release\%branch%\%BUILD%\amd64fre\debug.crit\symbols.pri c:\symbols *.* /MIR /Z /J /MT /NP /NFL /LOG:c:\copysymbols.log
