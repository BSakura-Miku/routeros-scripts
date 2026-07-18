# CN IPv4 address-list updater
# Downloads a RouterOS CN.rsc list, replaces the active list, and rolls back on failure.

:global CNUpdateRunning
:if ($CNUpdateRunning = true) do={
    :log warning "CNIP update skipped: another update is running"
    :return
}
:set CNUpdateRunning true

:local listName "CN"
:local backupList "CN_BACKUP"
:local fileName "pcie1/CN.rsc"
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
    :if ([:len [/file find where name=$fileName]] > 0) do={
        /file remove [find where name=$fileName]
    }

    :foreach item in=[/ip firewall address-list find where list=$listName] do={
        :local address [/ip firewall address-list get $item address]
        /ip firewall address-list add list=$backupList address=$address timeout=0 comment="CN rollback backup"
    }

    :local backupCount [/ip firewall address-list print count-only where list=$backupList]
    :if ($backupCount < $minCount) do={
        :error ("backup count too low: " . $backupCount)
    }

    /tool fetch url=$sourceURL mode=https dst-path=$fileName check-certificate=yes

    :if ([:len [/file find where name=$fileName]] = 0) do={
        :error "downloaded CN.rsc is missing"
    }

    :local fileSize [/file get [find where name=$fileName] size]
    :if ($fileSize < 100000) do={
        :error ("downloaded CN.rsc is too small: " . $fileSize)
    }

    /ip firewall address-list remove [find where list=$listName]
    /import file-name=$fileName

    :local newCount [/ip firewall address-list print count-only where list=$listName]
    :if (($newCount < $minCount) || ($newCount > $maxCount)) do={
        :error ("new CN count outside expected range: " . $newCount)
    }

    :log warning ("CNIP update succeeded, new count=" . $newCount)

    /ip firewall address-list remove [find where list=$backupList]
    :if ([:len [/file find where name=$fileName]] > 0) do={
        /file remove [find where name=$fileName]
    }
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
    :if ([:len [/file find where name=$fileName]] > 0) do={
        /file remove [find where name=$fileName]
    }
}

:set CNUpdateRunning false
