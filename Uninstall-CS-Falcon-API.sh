#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# MIT License
#
# Copyright (c) 2024 Alton Brailovskiy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# 
# Script to uninstall Crowdstrike inspired by: 
# richard@richard-purves.com - 05/04/2022 
# https://github.com/franton/Crowdstrike-API-Scripts
#  
# https://github.com/stevenwick/CrowdStrike-Falcon-Uninstall-Script
#
# Updated by Alton Brailovskiy in November 2024
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# check to make sure Crowdstrike Falcon is installed and skip if it isnt't.
if [ -d "/Applications/Falcon.app" ];
then
    echo "Crowdstrike detected. Starting uninstall."
    
    # Jamf Pro Variables. Use the $4 + $5 script parameters in Jamf to set client ID & secret
    clientid="$4"
    secret="$5"
    b64creds=$( printf "$clientid:$secret" | /usr/bin/iconv -t ISO-8859-1 | /usr/bin/base64 -i - )

    # API Base URL and the various endpoints we need
    # Do some autodetection to work out correct URL. Set to default if blank.
    baseurl="https://api.us-2.crowdstrike.com"
    baseurl=$( /usr/bin/curl -s -v -X POST -d "client_id=${clientid}&client_secret=${secret}" "${baseurl}/oauth2/token" 2>&1 | awk '($2 == "Location:") {print $3}' | cut -d/ -f1-3 )
	[ -z "$baseurl" ] && baseurl="https://api.us-2.crowdstrike.com"

    oauthtoken="$baseurl/oauth2/token"
    oauthrevoke="$baseurl/oauth2/revoke"
    maintenancetoken="$baseurl/policy/combined/reveal-uninstall-token/v1"

    # Get the Agent / Device ID from current the install
    AgentID=$(sudo /Applications/Falcon.app/Contents/Resources/falconctl stats | grep agentID | awk -F': ' '{print $2}' | tr -d '-')
    echo AgentID: $AgentID 

    # Request bearer access token using the API
    token=$( /usr/bin/curl -s -X POST "$oauthtoken" -H "accept: application/json" -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=${clientid}&client_secret=${secret}" )

    # Extract the bearer token from the json output above
    bearer=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$token" )

    # Retrieve the uninstall token for the current computer
    response=$(curl -X POST "$maintenancetoken" -H "authorization: Bearer $bearer" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{  \"audit_message\": \"Testing Jamf Pro Crowdstrike uninstall script\",  \"device_id\": \"$AgentID\"}")
    echo response: $response

    # Extract the uninstall token from the json output above
    uninstalltoken=$( echo "$response" | grep '"uninstall_token"' | awk -F'"' '{print $4}')
    echo Uninstall Token: $uninstalltoken

    # Uninstall Crowdstrike
    echo Starting Uninstall of Crowdstrike Falcon with the provided Uninstall / Maintenance token 
    echo $uninstalltoken | sudo /Applications/Falcon.app/Contents/Resources/falconctl uninstall --maintenance-token

    # Invalidate access to the bearer token
    echo starting bearer token invalidation...
    /usr/bin/curl -s -X POST "$oauthrevoke" -H "accept: application/json" -H "authorization: Basic ${b64creds}" -H "Content-Type: application/x-www-form-urlencoded" -d "token=${bearer}"
    echo Token has been invalidated... Exiting script

    #Remediate Falcon by redeploying it
    # Ensure you have an ongoing update inventory policy w/ the following custom trigger in order to then initiate a smart group recalculation to then initiate remediation and redeployment 
    sudo /usr/local/jamf/bin/jamf policy --trigger update-inventory ;
   	echo Updating Jamf Inventory
    # Ensyre your redeploy policy is scoped to the smart group with Falcon Not Installed as a group criteria. This wil effectivly reinstall falcon from scratct anytime a mac is added to that group 
    sudo /usr/local/jamf/bin/jamf policy --trigger r-falcon
	  echo redeployingg falcon with the policy from Jamf 
    exit 0

else
    echo "Crowdstrike not installed."
    exit 1
fi

# All done!
exit 0
