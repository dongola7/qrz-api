#!/bin/sh
# the next line restarts using tclsh \
exec tclsh "$0" "$@"

# Copyright (c) 2025, Blair Kitchen
# All rights reserved.
#
# See the file "license.terms" for informatio on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

package require Tcl 9.0
package require tdom 0.9.5
package require tls 1.8
package require http 2.10

http::register https 443 [list ::tls::socket -autoservername 1 -require 1]

namespace eval ::qrz {
    set loginInfo ""
    set sessionKey ""
}

proc ::qrz::xml2dict {domNode} { 
    set result [dict create]

    foreach child [$domNode childNodes] {
        set key [$child nodeName]

        foreach attr [$child attributes] {
            # handle namespaced attributes
            if {[llength $attr] != 1} {
                set attr [lindex $attr 0]
            }
            dict set result $key.$attr [$child getAttribute $attr]
        }

        if {[$child text] != ""} {
            set value [$child text]
        } else {
            set value [xml2dict $child]
        }

        dict set result $key $value
    }

    return $result
}

proc ::qrz::QueryApi {args} {
    variable sessionKey
    variable loginInfo

    if {$loginInfo == ""} {
        # there is no session. indicates login needs to be called
        error "missing session. did you call ::qrz::login?"
    }

    # If there is a sessionKey, try to use the current session
    if {$sessionKey != ""} {
        set result [RawGetUrl s $sessionKey {*}$args]
        if {[dict exists $result QRZDatabase Session Key]} {
            # Valid session included in result. We have
            # an authenticated response and can return
            return $result
        }
    }

    # There is no valid session. Try to create a new session
    set result [RawGetUrl {*}$loginInfo {*}$args]
    if {[dict exists $result QRZDatabase Session Key]} {
        set sessionKey [dict get $result QRZDatabase Session Key]
        return $result
    }

    # Something else went wrong. See if there is an error message
    if {[dict exists $result QRZDatabase Session Error]} {
        return -code error [dict get $result QRZDatabase Session Error]
    }

    # No error message returned, throw a generic error
    error "unknown error occurred"
}

proc ::qrz::RawGetUrl {args} {
    try {
        set baseUri "https://xmldata.qrz.com/xml/current"
        set query [http::formatQuery {*}$args]
        set url "$baseUri/?$query"

        set token [http::geturl $url]

        if {[http::status $token] != "ok"} {
            foreach {msg stackTrace errorCode} [http::error $token]
            error "error $errorCode: $msg"
        }

        set xml [http::data $token]
        set domDoc [dom parse $xml]
        set result [xml2dict $domDoc]
        $domDoc delete

        return $result
    } finally {
        if {[info exists token]} { http::cleanup $token }
    }
}

proc ::qrz::login {username password} {
    variable loginInfo
    variable sessionKey

    set sessionKey ""
    set loginInfo [list username $username password $password]
    set result [QueryApi]
    return $result
}

proc ::qrz::lookupCallsign {callsign} {
    set result [QueryApi callsign $callsign]

    if {[dict exists $result QRZDatabase Session Error]} {
        error [dict get $result QRZDatabase Session Error]
    }

    return $result
}

puts [qrz::login $env(QRZ_USERNAME) $env(QRZ_PASSWORD)]
puts [qrz::lookupCallsign KE2EHU]
