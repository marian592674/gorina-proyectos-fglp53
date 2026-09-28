Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\PROYECTOS\P003.Pick.Materiales.Insumos\iniciar_servidor_oculto.ps1", 0
Set WshShell = Nothing
