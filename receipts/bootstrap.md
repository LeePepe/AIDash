# Scheduled Pulse bootstrap receipt

- Date: 2026-11-10
- Branch: feat/aidash-scheduled-pulse
- Scope: only the three registered AIDash job labels

## com.tianpli.aidash.job.my-pr-supervisor
- plist: /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.my-pr-supervisor.plist
- bootstrap exit: 0
- launchctl print exit: 0
```text
	path = /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.my-pr-supervisor.plist
	state = not running
	program = /bin/zsh
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	last exit code = (never exited)
```

## com.tianpli.aidash.job.pr-auto-review
- plist: /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.pr-auto-review.plist
- bootstrap exit: 0
- launchctl print exit: 0
```text
	path = /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.pr-auto-review.plist
	state = not running
	program = /bin/zsh
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	last exit code = (never exited)
```

## com.tianpli.aidash.job.aidata-digest
- plist: /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.aidata-digest.plist
- bootstrap exit: 0
- launchctl print exit: 0
```text
	path = /Users/tianpli/Library/LaunchAgents/com.tianpli.aidash.job.aidata-digest.plist
	state = not running
	program = /bin/zsh
		PATH => /usr/bin:/bin:/usr/sbin:/sbin
	last exit code = (never exited)
```

Only the three com.tianpli.aidash.job.* labels above were targeted; the existing com.tianpli.aidash XPC label was not touched.
