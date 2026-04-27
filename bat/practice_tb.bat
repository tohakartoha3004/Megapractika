taskkill /im vsimk.exe /f
taskkill /im vish.exe /f
rmdir "..\questasim" /s /q
md "..\questasim"
call questasim -do ../tcl/practice_tb.tcl