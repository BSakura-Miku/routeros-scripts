# Compatibility entry point. The maintained copy is scripts/cloudflare-ddns-ipv6.rsc.
# Replace every YOUR_* value before importing or pasting into RouterOS.

:local CFAPITOKEN "YOUR_CLOUDFLARE_API_TOKEN"
:local CFZoneID "YOUR_CLOUDFLARE_ZONE_ID"
:local CFRecordID "YOUR_CLOUDFLARE_RECORD_ID"
:local CFDNSNAME "YOUR_DDNS_HOSTNAME"

:local WANInterface "pppoe-out1"
:local PUB6 ""

:foreach item in=[/ipv6 address print as-value where interface=$WANInterface] do={
    :local address ($item->"address")

    :if (([:pick $address 0 1] = "2") && (($item->"invalid") != true) && (($item->"disabled") != true) && (($item->"deprecated") != true)) do={
        :set PUB6 [:pick $address 0 [:find $address "/"]]
    }
}

:if ($PUB6 = "") do={
    :log error "CF-DDNS: no usable global IPv6 address found"
} else={
    :local apiURL ("https://api.cloudflare.com/client/v4/zones/" . $CFZoneID . "/dns_records/" . $CFRecordID)

    :do {
        :local getResponse [/tool fetch url=$apiURL mode=https http-method=get check-certificate=yes output=user as-value http-header-field=("Authorization: Bearer " . $CFAPITOKEN)]
        :local getBody [:deserialize from=json value=($getResponse->"data")]
        :local record ($getBody->"result")
        :local currentIPv6 ($record->"content")

        :if ((($getResponse->"status") != "finished") || (($getBody->"success") != true)) do={
            :error "Cloudflare record query failed"
        }

        :if ($PUB6 != $currentIPv6) do={
            :local putResponse [/tool fetch url=$apiURL mode=https http-method=put check-certificate=yes output=user as-value http-header-field=("Authorization: Bearer " . $CFAPITOKEN . ",Content-Type: application/json") http-data=("{\"type\":\"AAAA\",\"name\":\"" . $CFDNSNAME . "\",\"content\":\"" . $PUB6 . "\",\"ttl\":120,\"proxied\":false}")]
            :local putBody [:deserialize from=json value=($putResponse->"data")]

            :if ((($putResponse->"status") = "finished") && (($putBody->"success") = true)) do={
                :log info ("CF-DDNS: updated successfully from " . $currentIPv6 . " to " . $PUB6)
            } else={
                :error "Cloudflare record update failed"
            }
        }
    } on-error={
        :log error "CF-DDNS: HTTPS/API operation failed"
    }
}
