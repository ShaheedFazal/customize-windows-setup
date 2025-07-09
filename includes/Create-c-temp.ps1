# Create the C:\Temp folder if not exists
If (!(Test-Path $TEMPFOLDER)) {
    New-Item -ItemType Directory -Force -Path $TEMPFOLDER
}
