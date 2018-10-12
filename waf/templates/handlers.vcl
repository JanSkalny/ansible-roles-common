/* Security.vcl handlers VCL file
 * Copyright (C) 2009 Kacper Wysocki
 *
 * **************** handlers **************** *
 * The rest of the code assumes this file defines the
 * following:
 *   sec_honey   - the honeyput backend
 *   sec_log     - logging function
 *   sec_handler - this function handles all triggered rules
 *
 * If you do not intend on changing these there is no need to read on.
 */

sub sec_default_handler {
	call sec_log;

	# redirect to rick!
	#return (synth(777, "go away"));

	# default is reject
    call sec_reject;
}

# Here you can specify what gets logged when a rule triggers.
sub sec_log {
    std.log("security.vcl alert xid:" + req.xid + " " + req.proto
        + " [" + req.http.X-VSF-Module + "-" + req.http.X-VSF-RuleID + "]"
        + req.http.X-VSF-Client
        + " (" +  req.http.X-VSF-RuleName + ") ");
    #std.syslog(6, "<VSF> " + std.time2real(now) + " [" + req.http.X-VSF-RuleName + "/ruleid:" + req.http.X-VSF-RuleID + "]: " + req.http.X-VSF-ClientIP + " - " + req.http.X-VSF-Method + " http://" + req.http.X-VSF-URL + " " + req.http.X-VSF-Proto + " - " + req.http.X-VSF-UA);
}


/* You can define your own handlers here if you know a little vcl.
 * The default handlers are defined in main.vcl
 * remember that it must be referenced in the code above */

/* sample handler, contains sample code for all handler types */
sub sec_myhandler {
    # perform an action based on the error code as above.

    return (synth(800, "Blahblah")); # debug response

    set req.http.X-VSF-Response = "we don't like your kind around here";
    return (synth(801, "Rejected"));

    set req.http.X-VSF-Response = "http://u.rdir.it/hit/me/please";
    return (synth(802, "Redirect"));

    # send to sec_honey backend
    return (synth(803, "Honeypot me"));

    set req.http.X-VSF-Response = "<h1>Whatever</h1> so you think you can dance?";
    return (synth(804, "Synthesize"));

    return (synth(805, "Drop"));
}


