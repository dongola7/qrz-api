#!/bin/sh
# the next line restarts using tclsh \
exec tclsh "$0" "$@"

# Copyright (c) 2025, Blair Kitchen
# All rights reserved.
#
# See the file "license.terms" for informatio on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

#
# Performs a simple callbook lookup of the specified callsign. QRZ username
# and password should be specified via the QRZ_USERNAME and QRZ_PASSWORD
# environment variables, respectively.
#

package require http 2.10
package require tls 1.8

source [file join [file dirname [file normalize [info script]]] qrz.tcl]
package require qrz 0.1

# We want to use https when querying the API, so need to register https support
# in the http package
http::register https 443 [list ::tls::socket -autoservername 1 -require 1]

proc checkResult {result} {
    # Check for any informational messages
    if {[dict exists $result QRZDatabase Session Message]} {
        puts "Warning: [dict get $result QRZDatabase Session Message]"
    }
}

# Establish a session
set result [qrz::login $env(QRZ_USERNAME) $env(QRZ_PASSWORD)]
checkResult $result

set result [::qrz::lookupCallsign [lindex $argv 0]]
checkResult $result

foreach {key value} [dict get $result QRZDatabase Callsign] {
    puts "$key : $value"
}
