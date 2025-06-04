# customize-windows-client
PowerShell post-installation script to minimize and customize Windows operating systems.

## REQUIREMENTS
* PowerShell 5.1 or above 
* Use of RunAsAdministrator

## INSTALL AND USAGE
* Make sure that the requirements (see REQUIREMENTS) are fulfilled
* Download a zip file and uncompress it
* Adjust the settings and variables in section of the script to your environment and requirements. All scripts in the `includes` directory will be executed.
  * To disable a customization action, move its script into `includes/disabled` or delete it.
* The script locates the `includes` folder relative to its own path, so keep the directory structure intact.
* Start the PowerShell script using ```.\customize-windows-client.ps1```
* If ExecutionPolicy is restricted try to use: ```powershell -ExecutionPolicy Bypass .\customize-windows-client.ps1```

## CONTRIBUTION
In the current version, the script fulfills its purpose and leaves behind a tidy minimal Windows installation. The individual actions can certainly be optimized, especially with regard to error handling. Who feels addressed here is gladly invited to add meaningful new additions as action module or to adapt the existing ones. 

## SOURCE REFERENCES
The idea to use a separate script for each customization action as well as some actions were taken from the windows-trimify project. Thanks! (https://github.com/toolarium/windows-trimify/blob/master/LICENSE)

## LICENSE
customize-windows-client and all individual scripts are under the BSD 3-Clause license unless explicitly noted otherwise. Please refer to the LICENSE.

