#!/usr/bin/env node

var fs = require('fs')
var FB = require('fb')
var arg = {
	cmd: process.argv[2],
	token: process.argv[3],
	user_id: process.argv[4],
	}

var err = function(){console.error.apply(console.error,arguments); process.stdout.write('ERROR'); process.exit(1)}

var authf = 'arc/fb_auth.json'
if (!fs.existsSync(authf)) err("[fb-sdk] did not find auth file "+authf)
var auth = JSON.parse(fs.readFileSync(authf))

switch (arg.cmd) {default: err("bad command:",arg.cmd)
break; case 'verify':
	FB.api('/debug_token', {
		access_token: auth.id+'|'+auth.secret,
		input_token: arg.token,
		}, function(res){
			if (!res || res.error || (res.data&&res.data.error)) err("[fb-sdk] api error:",(res&&res.error)||(res&&res.data&&res.data.error))
			if (!res.data.is_valid) err("[fb-sdk] invalid access token")
			if (res.data.app_id !== auth.id) err("[fb-sdk] invalid app id:",res.data.app_id,"!=",auth.id)
			if (res.data.user_id !== arg.user_id) err("[fb-sdk] invalid user id:",res.data.user_id,"!=",arg.user_id)
		})
break; case 'get-name':
	FB.api('/me', {
		access_token: arg.token,
		}, function(res){
			if (!res || res.error || (res.data&&res.data.error)) err("[fb-sdk] api error:",(res&&res.error)||(res&&res.data&&res.data.error))
			process.stdout.write(res.name||"")
		})
// turns out we don't actually need to do this, since we're just using the access token as a password
// break; case 'extend':
	// FB.api('oauth/access_token', {
	// 	client_id: auth.id,
	// 	client_secret: auth.secret,
	// 	grant_type: 'fb_exchange_token',
	// 	fb_exchange_token: arg.token,
	// 	}, function(res){
	// 		if (!res || res.error) err("api error:",res&&res.error)
	// 		process.stdout.write(res.access_token)
	// 	})
}
