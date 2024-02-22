# FreeRadius Server Docker Image

FreeRadius Docker based on Ubuntu 20.04 LTS, optimized for ISP's.

# Environment Variables

| ENV                         | VALUE              | TYPE     |
|-----------------------------|--------------------|----------|
| MYSQL_HOST                  | mysql              | required |
| MYSQL_PORT                  | 3306               | required |
| MYSQL_DATABASE              | radius             | required |
| MYSQL_PASSWORD              | radpass            | required |
| MYSQL_USER                  | radius             | required |
| MYSQL_INIT                  | true               | optional |
| DEFAULT_CLIENT_SECRET       | testing123         | optional |
| EAP_USE_TUNNELED_REPLY      | true               | required |
| STATUS_ENABLE               | true               | optional |
| STATUS_CLIENT               | exporter           | optional |
| STATUS_SECRET               | adminsecret1       | optional |
| STATUS_INTERFACE            | eth0 (SWARM = eth1)| optional |
| PPP_VAN_JACOBSON_TCP_IP     | false              | optional |
| TZ                          | Europe/Bratislava  | optional |

## STATUS_ENABLE = true

```diff
server status {
        listen {
                #  ONLY Status-Server is allowed to this port.
                #  ALL other packets are ignored.
                type = status

-               ipaddr = 127.0.0.1
+               ipaddr = {$RADIUS_CONTAINER_IP}
                port = 18121
        }

        #
        #  We recommend that you list ONLY management clients here.
        #  i.e. NOT your NASes or Access Points, and for an ISP,
        #  DEFINITELY not any RADIUS servers that are proxying packets
        #  to you.
        #
        #  If you do NOT list a client here, then any client that is
        #  globally defined (i.e. all of them) will be able to query
        #  these statistics.
        #
        #  Do you really want your partners seeing the internal details
        #  of what your RADIUS server is doing?
        #
-       client admin {
+       client {$STATUS_CLIENT} {
-               ipaddr = 127.0.0.1
+               ipaddr = 0.0.0.0
-               secret = adminsecret
+               secret = {$STATUS_SECRET}
        }

        #
        #  Simple authorize section.  The "Autz-Type Status-Server"
        #  section will work here, too.  See "raddb/sites-available/default".
        authorize {
                ok

                # respond to the Status-Server request.
                Autz-Type Status-Server {
                        ok
                }
        }
}
```

## PPP_VAN_JACOBSON_TCP_IP = false

See [ASR 1002-X PPPoE problem with Virtual-Access sub-interfaces](https://community.cisco.com/t5/other-service-provider-subjects/asr-1002-x-pppoe-problem-with-virtual-access-sub-interfaces/td-p/2665369).

```diff
DEFAULT Framed-Protocol == PPP
-        Framed-Protocol = PPP,
-        Framed-Compression = Van-Jacobson-TCP-IP
+        Framed-Protocol = PPP
+        #Framed-Compression = Van-Jacobson-TCP-IP
```
