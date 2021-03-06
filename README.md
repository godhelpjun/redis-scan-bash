
## redis-scan

### Changes

#### 0.5.0 (June 9)

- Limit reached exit code changed from 3 to 60
- Fixes related to Pygments (pygmentize -l json)
- `get` each command (will render pretty JSON)
- `length` each command for length of string (strlen) or collection (llen, hlen, scard, zcard) by first checking `type`
- `value` each command to get key or sample collection 
- `@quiet` to not echo the each command/key

#### 0.4.0 

Use `~/redis-scan-bash/bin/redis-scan.sh` which you can alias in `~/.bashrc` as per instructions further below. 

The `bin/bashrc.redis-scan.sh` and `rhloggin.sh` files must no longer to imported into your `~/.bashrc.`

### Problem

We know we must avoid `redis-cli keys '*'` especially on production servers with many keys, since that blocks other clients for a significant time e.g. more than 250ms, maybe even a few seconds. That might mean all current requests by users of your website are delayed for that time. Those will be recorded in your `slowlog` which you might be monitoring, and so alerts get triggered etc. Let's avoid that.

### Solution

Here is a Redis scanner aliased as `redis-scan` to use `SCAN` iteratively.

Extra features:
- match type of keys e.g. string, list, zset, set, hash
- perform a command on each matching key e.g. `llen`

It's brand new and untested, so please test on a disposable VM against a disposable local Redis instance, in case it trashes your Redis keys. As per the ISC license, the author disclaims any responsibility for any unfortunate events resulting from the disastrous use of this bash function ;)

Let me know any issues via Twitter (https://twitter.com/@evanxsummers) or open an issue on Github.

<img src="https://evanx.github.io/images/rquery/redis-scan-bash-featured.png">


### Examples

Let's turn on debug logging in our shell to see what `redis-scan` is doing:
```shell
export RHLEVEL=debug
```

Scan all keys:
```shell
redis-scan '*'
```
Actually, there is a `eachLimit` (default 1000) so it will only scan 1000 keys (in batches, with sleeps inbetween), print a message "Limit reached" and custom exit code of `60.`

If the first parameter is a number prefixed with `@` then it is taken as the database number:
```shell
redis-scan @2
```
where this scans database number `2` via `redis-cli -n 2`

We can and should use `match` to reduce the number of keys.
```shell
redis-scan match 'demo:*'
```
If a parameter contains an asterisk, then `match` is assumed:
```shell
redis-scan 'article:*'
```

#### Match type

We can filter the keys by type using an `@` prefix (rather than dashes):
```shell
redis-scan match 'feed:*' @set
```
where supported types are: `string, list, hash, set, zset.`


#### Each command

We can specify an "each" command to be executed for each matching key:
```shell
redis-scan @13 @hash -- hlen
```
where we use a double-dash to delimit the `each` command. In this case we execute `hlen` against each key of type `hash`

Actually the script knows that `hlen` is a hashes command, and so `@hash` can be omitted:
```shell
redis-scan @13 -- hlen
```
where this will scan all keys in db `13,` and for each hashes key, print its `hlen.`

Incidently above is equivalent to the following command using `xargs`
```shell
redis-scan -n 13 @hash | xargs -n1 redis-cli -n 13 hlen
```

The following should print `set` for each, since we are filtering sets.
```shell
redis-scan @set -- type
```

Print the first five (left) elements of all list keys:
```shell
redis-scan -- lrange 0 4
```

Initial scan of matching sets:
```shell
redis-scan 'rp:*' -- sscan 0
```
where `redis-cli sscan KEY 0` is invoked on each set key matching `rp:*`

Print hash keys:
```shell
redis-scan 'rp:*' -- hkeys
```

Print hashes:
```shell
redis-scan 'rp:*' -- hgetall
```

Print the `length` of the key by checking its `type` and then one of: `strlen llen hlen scard zcard`
```shell
redis-scan '*' -- length
```

#### JSON formatting

Note that by default the script will try to format values resembling JSON, using `python` and also `pygmentize` if available.

You can install `pygmentize` as follows:
```shell
sudo easy_install Pygments
sudo easy_install Pygments-json
```
where we assume you have `python` and its `easy_install` utility installed on your system.

<img src="https://evanx.github.io/images/redis-scan-bash/redis-scan-hgetall-json.png">

#### Settings

We disable the `eachLimit` by setting it to `0` at the beginning of the command-line as follows:
```shell
eachLimit=0 redis-scan @hash match 'some keys' -- ttl
```

To force the `each` command if it dangerous e.g. `del,` we must set `commit` as follows:
```shell
commit=1 eachLimit=0 redis-scan @hash match 'some keys' -- ttl
```
where actually `commit` is not required for `ttl` but I'd rather not risk putting `del` in any examples.

Alternatively we can use `@nolimit` and `@commit` directives:
```shell
redis-scan @hash @nolimit match 'some keys' -- ttl @commit
```
where the `@` directives can be specified before or after the double-dash delimiter.

The scan sleep duration can be changed as follows:
```shell
scanSleep=1.5 redis-scan
```
where the duration is in seconds, with decimal digits allowed, as per the `sleep` shell command.

#### Clean up

The script creates a temp dir `~/.redis-scan/tmp` where it writes files prefixed with its PID:
- `$$.run` contains the PID itself i.e. the value of `$$`
- `$$.scan` contains the output from the `SCAN` command
- `$$.each` contains output from the `eachCommand`

When the script errors or completes successfully, it will try delete these files, and also find any such files older than 7 days and delete those.

Note that you can abort execution from a different shell by:
- deleting a specific `$$.run` file to terminate that script
- deleting all files in `~/.redis-scan/tmp` (terminate all)
- deleting the directory `~/.redis-scan/tmp` (terminate all)


### Performance considerations

When we have a large number of matching keys, and are performing a `type` check and executing a command on each key e.g. `expire,` we could impact the server and other clients, so we mitigate this:

- by default there is an `eachLimit` of 1000 keys scanned, then exit with error code 1
- before `SCAN` with the next cursor, sleep for 5ms (hard-coded)
- additionally before next scan, sleep for long `scanSleep` (default duration of 250ms)
- if the slowlog length increases, double the sleep time e.g. from 250ms to 500ms
- before key type check, sleep for 5ms (hard-coded)
- sleep `eachCommandSleep` (25ms) before any specified each command is executed
- while the load average (truncated integer) is above `loadavgLimit` sleep in a loop to wait until it's within this limit
- if `loadavgKey` is set, then ascertain the current load average from that Redis key
- if `uptimeRemote` is set, then ascertain the current load average via ssh

The defaults themselves are set in the script, and overridden, as follows:
```shell
  eachLimit=${eachLimit-1000} # limit of keys to scan, pass 0 to disable
  scanSleep=${scanSleep-0.250} # sleep 250ms between each scan
  eachCommandSleep=${eachCommandSleep-0.025} # sleep 25ms between each command
  loadavgLimit=${loadavgLimit-1} # sleep while local loadavg above this threshold
  loadavgKey=${loadavgKey-} # ascertain loadavg from Redis key on target instance
  uptimeRemote=${uptimeRemote-} # ascertain loadavg via ssh to remote Redis host
```

So the defaults can be overridden via the command-line passing, or via shell `export`

Also note that speed can increased using `COUNT` higher than the default value of `10`
```shell
redis-scan 'rp:*' count 100
```
In this case, the `scanSleep` happens after every 100 keys rather than every 10 keys, and so the script will run 10x faster.

In future the script should notice the higher count, and perhaps adapt its sleeping somehow.


#### Long runs

Consider that the script is being applied to change the expiry of a large number of keys.

Generally speaking, one wants conversative sleep times to minimise the impact on production machines. This might mean longer runs, e.g. overnight using `nohup.`

You can roughly work out how long a full scan will take by timing the run for 1000 keys, and factoring the time for the total number of keys. If it's too many days perhaps, you can override the settings `scanSleep` and `eachCommandSleep` with shorter durations. However, you should monitor your system during these runs to ensure it's not too adversely affected.

We can effectively pause long runs by simulating a high load on the host of the target Redis instance via the `loadavgKey` described below.

#### Remote loadavg

If running against a remote instance, you can:
- specify `uptimeRemote` for ssh, to determine its loadavg via `ssh $uptimeRemote uptime`
- alternatively specify `loadavgKey` to read the load average via Redis

Then the script can pause when the load average of the remote Redis host is high.

##### uptimeRemote

An ssh remote `user@host` can be specified for `uptime.` This access could be via an ssh forced command.

Test as follows:
```shell
  ssh $uptimeRemote uptime | sed -n 's/.* load average: \([0-9]*\)\..*/\1/p'
```

##### loadavgKey

Alternatively when using `loadavgKey` you could run a minutely cron job on the Redis host:
```shell
minute=`date +%M`
while [ `date +%M` -eq $minute ] # util the minute of the clock changes
do
  redis-cli -n 13 setex 'cron:loadavg' 90 `cat /proc/loadavg | cut -d' ' -f1` | grep -v OK
  sleep 13
done
```
where a sleep duration of 13 seconds is choosen, since it has a factor closely exceeding 60 seconds. When the minute changes we exit.

You can test our cron script as follows:
```
~/redis-scan-bash$ bash bin/cron.minutely.set.loadavg.redis.sh 'cron:loadavg' DBN
```
But beware it will set that key and the specified Redis instance.

Then into the crontab, specifying the key and database number or numbers on which to set this key:
```
* * * * * ~/redis-scan-bash/bin/cron.minutely.set.loadavg.redis.sh "cron:loadavg" <dbns>
```

We can monitor it:
```shell
redis-cli -n 13 ttl cron:loadavg
```
```
(integer) 79
```
```shell
redis-cli -n 13 get cron:loadavg
```
```
"0.01"
```

#### Each commands

Currently we support the following "each" commands:
- key meta data: `type` `ttl`
- key expiry and deletion: `persist` `expire` `del`
- string: `get`
- set: `scard smembers sscan`
- zset: `zrange zrevrange zscan`
- list: `llen lrange`
- hash: `hlen hgetall hkeys hscan`

However the scan commands must have cursor `0` i.e. just the first batch

### Installation

Let's grab the repo into our home directory.
```shell
( set -e
  cd
  git clone https://github.com/evanx/redis-scan-bash
  ls -l redis-scan-bash/bin
)
```

We alias `redis-scan` for for shell:
```shell
alias redis-scan=~/redis-scan-bash/bin/redis-scan.sh
```
where this assumes that the repo has been cloned to `~/redis-scan-bash`

Later, drop this into your `~/.bashrc` for next time.

Now we can try `redis-scan` in this shell:
```shell
redis-scan
redis-scan @set
redis-scan @hash match '*'
redis-scan @set -- ttl
```

### Troubleshooting

To enable debug logging:
```shell
export RHLEVEL=debug
```

To disable debug logging:
```shell
export RHLEVEL=info
```

### Further plans

- regex for filtering keys
- refactor as a standalone bash script not necessarily via bashrc (DONE)
- write a Node version

When a future Node version has V8 supporting async/await so Babel not is required and start up time is quick.

Then Node will be an excellent choice for console apps like this.

Hopefully I will be inspired to write the Node version in meantime, even though it will not be as useful because of slow startup.

### Upcoming refactor (DONE)

I'll be refactoring to externalise the `RedisScan` function from `bashrc`

Then it can be included in your `PATH` or aliased in `bashrc` as follows:
```shell
alias redis-scan=~/redis-scan-bash/bin/redis-scan.sh
```

Then the script can `set -e` i.e. exit on error, with an exit trap to cleanup. Also then it can be split into multiple functions to be more readable and avoid some repetitive code.

It was originally intended to be a simple function that I would paste into `bashrc` but it became bigger than expected. Consequently it has some code repetition for short term pragmatism, but which violates the DRY principle.

#### set -e

By the way, I'm a firm believer that bash scripts should `set -e` from the outset:
- we must handle nonzero returns, otherwise the script will exit
- the exit trap should alert us that the script has aborted on error
- in this case, the nonzero exit code can be `$LINENO` for debugging purposes

This enforces the good practice of handling errors, and vastly improves the robustness of bash scripts.

In development/testing:
- aborts force us to handle typical errors

In production:
- we abort before any damage is done

It's easy to reason about the state, when we know that all commands succeeded, or otherwise their nonzero returns were handled appropriately.

So for your next bash script, try `set -e` and persevere. It's worth it :)

### Contact

- https://twitter.com/@evanxsummers

### Further reading

- https://github.com/evanx/redishub
