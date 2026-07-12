# CN IPv4 address-list updater
# Downloads a RouterOS CN.rsc list, replaces the active list, and rolls back on failure.

:global CNUpdateRunning
:if ($CNUpdateRunning = true) do={:return}
:set CNUpdateRunning true

:local listName "CN"
:local backupList "CN_BACKUP"
:local fileName "CN.rsc"
:local logFile "temp_log.txt"
:local sourceURL "https://gh-proxy.org/https://raw.githubusercontent.com/ruijzhan/chnroute/master/CN.rsc"
:local minCount 6000
:local maxCount 10000

:do {
    :local oldCount [/ip firewall address-list print count-only where list=$listName]
    :log warning ("CNIP update started, current count=" . $oldCount)

    :if ($oldCount < $minCount) do={
        :error ("existing CN count too low: " . $oldCount)
    }

    /ip firewall address-list remove [find where list=$backupList]
    :if ([:len [/file find where name=$fileName]] > 0) do={/file remove [find where name=$fileName]}
    :if ([:len [/file find where name=$logFile]] > 0) do={/file remove [find where name=$logFile]}

    :foreach item in=[/ip firewall address-list find where list=$listName] do={
        :local address [/ip firewall address-list get $item address]
        /ip firewall address-list add list=$backupList address=$address timeout=0 comment="CN rollback backup"
    }

    :local backupCount [/ip firewall address-list print count-only where list=$backupList]
    :if ($backupCount < $minCount) do={
        :error ("backup count too low: " . $backupCount)
    }

    /tool fetch url=$sourceURL mode=https dst-path=$fileName check-certificate=yes
    :delay 2s

    :if ([:len [/file find where name=$fileName]] = 0) do={
        :error "downloaded CN.rsc is missing"
    }

    /ip firewall address-list remove [find where list=$listName]
    /execute script=("/import " . $fileName) file="temp_log"
    :delay 30s

    :local newCount [/ip firewall address-list print count-only where list=$listName]
    :if (($newCount < $minCount) || ($newCount > $maxCount)) do={
        :error ("new CN count outside expected range: " . $newCount)
    }

    :log warning ("CNIP update succeeded, new count=" . $newCount)

    /ip firewall address-list remove [find where list=$backupList]
    :if ([:len [/file find where name=$fileName]] > 0) do={/file remove [find where name=$fileName]}
    :if ([:len [/file find where name=$logFile]] > 0) do={/file remove [find where name=$logFile]}
} on-error={
    :local currentCount [/ip firewall address-list print count-only where list=$listName]
    :local backupCount [/ip firewall address-list print count-only where list=$backupList]

    :if (($currentCount < $minCount) && ($backupCount >= $minCount)) do={
        /ip firewall address-list remove [find where list=$listName]

        :foreach item in=[/ip firewall address-list find where list=$backupList] do={
            :local address [/ip firewall address-list get $item address]
            /ip firewall address-list add list=$listName address=$address timeout=0
        }

        :log error ("CNIP update failed; restored backup count=" . [/ip firewall address-list print count-only where list=$listName])
    } else={
        :log error ("CNIP update failed; current count=" . $currentCount . ", backup count=" . $backupCount)
    }

    /ip firewall address-list remove [find where list=$backupList]
    :if ([:len [/file find where name=$fileName]] > 0) do={/file remove [find where name=$fileName]}
    :if ([:len [/file find where name=$logFile]] > 0) do={/file remove [find where name=$logFile]}
}

:set CNUpdateRunning false
