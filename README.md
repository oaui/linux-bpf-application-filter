# IPTABLES / UFW Application filter (SSH, OpenVPN)
## Conntrack -/ Connmark & IPSet & SimpleProxy

## 1. How it works
Using the **[BPF module](https://www.ibm.com/docs/en/qsip/7.4.0?topic=queries-berkeley-packet-filters)**, which is implemented into the iptables functionality on the linux kernel, we can exactly determine, which packet we would like to match.
*[Wireshark](https://wireshark.org)* helps us, to inspect the data, which is sent in the Layer 7 header of the TCP packet *[Example](https://external-content.duckduckgo.com/iu/?u=https%3A%2F%2Fmedia.geeksforgeeks.org%2Fwp-content%2Fuploads%2F20230624200917%2FTCP-packet-format.jpg&f=1&nofb=1&ipt=e4bf3645c70e200a66d7b4546bc42f96831c16813b999ae938baf14379beb744)*. 
We are then able to match either 4 bytes, which would equal something like `SSH2.0-`, or 8 bytes using the `&&` within the *[BPF compiler](https://github.com/SnoopWS/nbpf-compiler/blob/main/nbpf_compile.c)*, to match for example `SSH2.0-libssh`. 

## 2. Why this is important
If we are only running one specifiy application on that port, for example SSH (or OpenVPN), this implementation allows us, to match the applications signature packet, which is (in most cases) sent at 3rd from a clients perspective: SYN-> SYNACK<- ACK-> PSH,ACK->
The PSH,ACK contains our data, which we want to match using the BPF.
Tools like `tcpdump` allow us, to take a packet capture of the process above and extract the needed bytes (or text/hex string).

## 3. Why is CONNMARK important?

`connmark` lets us set a mark on the entire connection of a singular packet. By doing this, we can "tag" the described PSH,ACK packet using the BPF and CONNMARK together: 
### The complex version
`iptables -t mangle -A PREROUTING -p tcp -m comment --comment "SSH Validation" -m connbytes --connbytes 3:3 --connbytes-mode packets --connbytes-dir original -m bpf --bytecode "23,48 0 0 0,84 0 0 240,21 0 19 64,48 0 0 9,21 0 17 6,40 0 0 6,69 15 0 8191,177 0 0 0,80 0 0 13,69 0 12 8,69 0 11 16,64 0 0 20,21 8 0 1397966893,80 0 0 20,21 0 7 1,80 0 0 21,21 0 5 1,80 0 0 22,21 0 3 8,64 0 0 32,21 0 1 1397966893,6 0 0 65535,6 0 0 0" -j CONNMARK --set-mark 1`. 
### The simplified version of this
`iptables -t mangle -A PREROUTING -p tcp -m string --string "SSH2.0-" --algo bm -j CONNMARK --set-mark 1`
Both are basically the same. The first one has the restriction, to only match the 3rd packet, like already described above and the exact BPF bytecode for the match.
`connbytes` is not need at all, like the 2nd example shows.

## 4. How can we use the mark?
- First, we have to restore the marked connection from the `-j CONNMARK` jump: `iptables -t mangle -A PREROUTING -p tcp -m comment --comment "Restore Mark" -m conntrack --ctstate NEW,ESTABLISHED -j CONNMARK --restore-mark` to the current connection. 
- Then, we can simply use conntrack, to allow all `ESTABLISHED` packets from this exact connection `iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate ESTABLISHED -m connmark --mark 1 -j ACCEPT`
- Then we accept all `NEW`, basically SYN packets: `iptables -t mangle -A PREROUTING -p tcp --syn -m conntrack --ctstate NEW -j ACCEPT`
- And set the policy of the mangle chain to DROP: `iptables -t mangle -P PREROUTING DROP`

### Only valid SSH connections will now pass into our NIC and invalid/non-SSH connections will be dropped by the policy.

## 5. SimpleProxy
- `apt install simpleproxy -y`
- `simpleproxy -d -L FRONTEND_PORT -R BACKEND_IP:BACKEND_PORT`
  - `-d`: detached mode
  - `-L`: listener port
  - `-R` reverse target
 
## Conclusion
iptables / BPF is only filtering on the NIC of our hardware which means that every packet which already passed into the NIC (that did not get filtered by origin firewall(s)), is seen and displayed. 
Application Filters will not magically "remove" traffic in our server. They only set, who is allowed to access our server and who is not allowed to access our server.
By 2026, there are stronger mechanisms such as edge firewall or load balancing, to distribute traffic and handle bad packets, yet, iptables and kernel modules are still an interesting way, of controlling traffic flow and protecting applications.
  
