# ARP / IPv6 Neighbor -> Firewall Address List
# Classifies devices by ARP comment keywords and maintains IPv4/IPv6 address lists.

:global SyncArpRunning
:if ($SyncArpRunning = true) do={:return}
:set SyncArpRunning true

:local autoPrefix "AUTO_ARP | "
:local v4Timeout 1d
:local v4RefreshThreshold 1h
:local v6Timeout 2h
:local v6RefreshThreshold 15m

:local newV4 0
:local newV6 0
:local migratedV4 0
:local migratedV6 0
:local refreshedV4 0
:local refreshedV6 0

:onerror syncError in={
    :foreach arpId in=[/ip arp find] do={
        :local v4Address [/ip arp get $arpId address]
        :local macAddress [/ip arp get $arpId mac-address]
        :local deviceComment [/ip arp get $arpId comment]
        :local targetList ""

        # Later matches have higher priority: service > guest > bt > iot > proxy.
        :if ($deviceComment ~ "proxy|Proxy|PROXY") do={:set targetList "proxy_clients"}
        :if ($deviceComment ~ "iot|IoT|IOT") do={:set targetList "iot_devices"}
        :if ($deviceComment ~ "bt|BT|Bt") do={:set targetList "bt_downloader"}
        :if ($deviceComment ~ "guest|Guest") do={:set targetList "guest_devices"}
        :if ($deviceComment ~ "service|Service") do={:set targetList "important_services"}

        :if (([:len $targetList] > 0) && ([:len $v4Address] > 0) && ([:len $macAddress] > 0)) do={
            :local autoComment ($autoPrefix . $deviceComment)
            :local v4Entries [/ip firewall address-list find where list=$targetList and address=$v4Address]
            :local hadV4Entry ([:len $v4Entries] > 0)
            :local keepV4Entry false

            :foreach entryId in=$v4Entries do={
                :if (![/ip firewall address-list get $entryId dynamic]) do={
                    :set keepV4Entry true
                } else={
                    :local oldComment [/ip firewall address-list get $entryId comment]
                    :local remaining [/ip firewall address-list get $entryId timeout]

                    :if ([:pick $oldComment 0 11] != $autoPrefix) do={
                        /ip firewall address-list remove $entryId
                        :set migratedV4 ($migratedV4 + 1)
                    } else={
                        :if ($remaining <= $v4RefreshThreshold) do={
                            /ip firewall address-list remove $entryId
                            :set refreshedV4 ($refreshedV4 + 1)
                        } else={
                            :set keepV4Entry true
                        }
                    }
                }
            }

            :if (!$keepV4Entry) do={
                /ip firewall address-list add list=$targetList address=$v4Address comment=$autoComment timeout=$v4Timeout
                :if (!$hadV4Entry) do={:set newV4 ($newV4 + 1)}
            }

            :foreach neighborId in=[/ipv6 neighbor find where mac-address=$macAddress] do={
                :local v6Address [/ipv6 neighbor get $neighborId address]

                :if (([:pick $v6Address 0 1] = "2") || ([:pick $v6Address 0 2] = "fd")) do={
                    :local v6Key ($v6Address . "/128")
                    :local v6Entries [/ipv6 firewall address-list find where list=$targetList and address=$v6Key]
                    :local hadV6Entry ([:len $v6Entries] > 0)
                    :local keepV6Entry false

                    :foreach entryId in=$v6Entries do={
                        :if (![/ipv6 firewall address-list get $entryId dynamic]) do={
                            :set keepV6Entry true
                        } else={
                            :local oldComment [/ipv6 firewall address-list get $entryId comment]
                            :local remaining [/ipv6 firewall address-list get $entryId timeout]

                            :if ([:pick $oldComment 0 11] != $autoPrefix) do={
                                /ipv6 firewall address-list remove $entryId
                                :set migratedV6 ($migratedV6 + 1)
                            } else={
                                :if ($remaining <= $v6RefreshThreshold) do={
                                    /ipv6 firewall address-list remove $entryId
                                    :set refreshedV6 ($refreshedV6 + 1)
                                } else={
                                    :set keepV6Entry true
                                }
                            }
                        }
                    }

                    :if (!$keepV6Entry) do={
                        /ipv6 firewall address-list add list=$targetList address=$v6Key comment=$autoComment timeout=$v6Timeout
                        :if (!$hadV6Entry) do={:set newV6 ($newV6 + 1)}
                    }
                }
            }
        }
    }

    :if (($newV4 + $newV6 + $migratedV4 + $migratedV6 + $refreshedV4 + $refreshedV6) > 0) do={
        :log info ("ARP sync: new=" . $newV4 . "/" . $newV6 . ", migrated=" . $migratedV4 . "/" . $migratedV6 . ", refreshed=" . $refreshedV4 . "/" . $refreshedV6)
    }
} do={
    :log error ("ARP sync failed: " . $syncError)
}

:set SyncArpRunning false
