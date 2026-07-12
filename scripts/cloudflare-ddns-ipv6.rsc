# Cloudflare IPv6 DDNS
# Updates an AAAA record only when the PPPoE global IPv6 address changes.

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
    :global CFLastIPv6

    :if ($PUB6 != $CFLastIPv6) do={
        :local apiURL ("https://api.cloudflare.com/client/v4/zones/" . $CFZoneID . "/dns_records/" . $CFRecordID)

        :do {
            :local response [/tool fetch url=$apiURL mode=https http-method=put check-certificate=yes output=user as-value http-header-field=("Authorization: Bearer " . $CFAPITOKEN . ",Content-Type: application/json") http-data=("{\"type\":\"AAAA\",\"name\":\"" . $CFDNSNAME . "\",\"content\":\"" . $PUB6 . "\",\"ttl\":120,\"proxied\":false}")]
            :local result [:deserialize from=json value=($response->"data")]

            :if ((($response->"status") = "finished") && (($result->"success") = true)) do={
                :set CFLastIPv6 $PUB6
                :log info ("CF-DDNS: updated successfully to " . $PUB6)
            } else={
                :log error "CF-DDNS: API returned unsuccessful response"
            }
        } on-error={
            :log error "CF-DDNS: HTTPS/API update failed"
        }
    }
}
