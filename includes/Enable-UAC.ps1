# Enable UAC
Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name EnableLUA -Value 1 -Type DWord

# Set User Account Control (UAC) to 'Notify only when apps try to make changes'
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
  -Name "ConsentPromptBehaviorAdmin" -Value 5
