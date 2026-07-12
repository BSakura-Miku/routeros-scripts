# mihomo end-to-end health check
# Tests the selected proxy in Final and toggles a RouterOS policy route after failures.

:local mihomoAddress "10.10.2.6"
:local controllerPort "9090"
:local apiSecret "YOUR_MIHOMO_API_SECRET"
:local routeComment "ROUTE_PRIMARY_IMM(Check Gateway)"
:local failureThreshold 3

:global MihomoHealthFailCount
:if ([:typeof $MihomoHealthFailCount] = "nothing") do={
    :set MihomoHealthFailCount 0
}

:local routeId [/ip route find where comment=$routeComment]

:if ([:len $routeId] = 0) do={
    :log error ("Mihomo health: route not found: " . $routeComment)
} else={
    :local healthURL ("http://" . $mihomoAddress . ":" . $controllerPort . "/proxies/Final/delay?url=http%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=8000")
    :local healthOK false

    :do {
        :local response [/tool fetch url=$healthURL http-header-field=("Authorization: Bearer " . $apiSecret) output=user as-value]
        :if (($response->"status") = "finished") do={
            :set healthOK true
        }
    } on-error={
        :set healthOK false
    }

    :if ($healthOK) do={
        :set MihomoHealthFailCount 0

        :if ([/ip route get $routeId disabled]) do={
            /ip route enable $routeId
            :log warning "Mihomo health restored: primary proxy route enabled"
        }
    } else={
        :set MihomoHealthFailCount ($MihomoHealthFailCount + 1)
        :log warning ("Mihomo health check failed " . $MihomoHealthFailCount . "/" . $failureThreshold)

        :if ($MihomoHealthFailCount >= $failureThreshold) do={
            :if (![/ip route get $routeId disabled]) do={
                /ip route disable $routeId
                :log error "Mihomo unhealthy: primary route disabled, fallback to PPPoE"
            }
        }
    }
}
