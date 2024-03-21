###
# ==++==
#
# Copyright (C) 2020-2024 Ajoro and MineStat contributors.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
###
@{
  GUID = '9adc7f28-e495-424d-83ef-8e48b08b5909'
  Author = "Ajoro and MineStat contributors"
  CompanyName = "Frag Land"
  Copyright = "(C) 2020-2024 Ajoro and MineStat contributors"
  HelpInfoUri = "https://github.com/FragLand/minestat/tree/master/PowerShell"
  ModuleVersion = "3.0.1"
  PowerShellVersion = "5.0"
  RootModule = "MineStat.psm1"
  Description = "MineStat is a Minecraft server connection status checker."
  CmdletsToExport = @()
  FunctionsToExport = @('MineStat')
  VariablesToExport = '*'
  AliasesToExport = @()
  PrivateData = @{
    PSData = @{
      Tags = @('Minecraft', 'Linux', 'MacOS', 'Windows', 'PSEdition_Desktop', 'PSEdition_Core')
      ProjectUri = "https://github.com/FragLand/minestat"
      LicenseUri = "https://www.gnu.org/licenses/gpl-3.0.txt"
      ReleaseNotes = @'
## 3.0.1
- Fix latency being overwritten
- Added support for splitting "Address:Port:Protocol" in address input (port/protocol "overwrite")

## 3.0.0
- Added support for Query / GameSpot4 / UT3 protocol.
- Combined motd_1 and motd_2 (bedrock_raknet)
- Added ignoreSRV option to not do SRV lookup
- Now chooses first if multiple SRV records
- Fixed some motds not being stripped or formatted correctly

## 2.0.6
- Added support for SRV record (RFC 2782)

## 2.0.5
- Renamed connstatus to connection_status
- Hide empty motd_2 (bedrock_raknet)
- Add scriptversion to verbose output
- Fix verbose output not displaying currentstatus

## 2.0.4
- Exposed connstatus

## 2.0.3
- Fix bug parsing "§" on powershell version 5
- Add support for splitting "Address:Port" in address input
- Add formatting/color reset in formatted_motd

## 2.0.2
- Fix release notes
- Add link to license
- Add more tags

## 2.0.1
- Convert script to module

## 2.0.0
- Add Bedrock, JSON, legacy, and extended legacy support
- Add support for MotD stripping
- Add $formatted_motd to display MotD with escaped unicode character in console

## 1.0.0
- Initial release
'@
    }
  }
}
