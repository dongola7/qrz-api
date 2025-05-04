# Copyright (c) 2025, Blair Kitchen
# All rights reserved.
#
# See the file "license.terms" for informatio on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

#
# This Tcl package provides a basic wrapper around the QRZ XML Callbook Data
# Service (https://www.qrz.com/page/xml_data.html). The API provides for
# authentication and session management.
#
# The QRZ XML Callbook Data Service operates using both http and https
# protocols. This package defaults to use of https. It is recommended the API
# caller register proper https support with the Tcl http package using
# the tls package or similar. Should the caller not wish to use https, it may
# be disabled in favor of the http protocol when calling the ::qrz::login
# function.
#
package require Tcl 9.0
package require tdom 0.9.5
package require http 2.10

package provide qrz 0.1

namespace eval ::qrz {
    # Stores the username/password used to successfully login to the service.
    # The login information is reused when the underlying session expires and
    # a new session is required.
    set loginInfo ""
    set sessionKey ""

    # Protocol to be used when connecting to the API
    set protocol "https"
}

#
# Helper function to convert an XML document into a Tcl dictionary, represented
# as a domNode returned from "dom parse". Each element in the XML document is
# represented as a key in the corresponding Tcl dictionary. Any attributes on
# an element are stored using they key <element-name>.<attribute-name>.
#
# Input is a domNode as returned by the tdom packaged "dom parse" function.
# Output is a Tcl dict.
#
# NOTE: This function is recursive, with a recursive call for each nested
#       element. Be cautious when using on deeply nested XML documents.
#
# For example:
#   <e1>
#     <e2 attr1="1">e2_value</e2>
#     <e3>
#       <e4>e4_value</e4>
#     </e3>
#   </e1>
#
# Becomes:
#   [dict create \
#       e1 [dict create \
#           e2.attr1 1 \
#           e2 e2_value \
#           e3 [dict create \
#               e4 e4_value \
#           ] \
#       ] \
#   ]
#
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

#
# Internal use only. Helper function used to query the qrz API and return the
# API response. Accepts a variable length of key/value pairs which are encoded
# to form the API query. The session does NOT need to be included in the
# key/value pairs. The primary purpose of this function is to abstract
# away the session management logic from upstream callers.
#
# When called, the function ensures there is a session established. If not,
# the function attempts to establish a session. If a session expires during
# an API call, the function will also try to establish a new session.
#
# It is an error to call this function prior to ::qrz::login being called.
#
# The function returns a Tcl dict of the QRZ API response or an error if
# something goes wrong.
#
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

#
# Internal use only. Helper function called by ::qrz::QueryApi to execute the
# actual query. The function takes a variable list of key/value pairs which are
# encoded as part of the GET query. It returns a Tcl dict representing the API
# response. The dict is of the format returned by ::qrz::xml2dict.
#
# This function does NOT perform any session handling. If a session is required
# for the API call, it must be included as one of the key/value pairs in the
# variable argument list.
#
proc ::qrz::RawGetUrl {args} {
    variable protocol
    try {
        set baseUri "$protocol://xmldata.qrz.com/xml/current"
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

#
# Establishes an API session with the specified username and password. This
# function MUST be called prior to executing any API queries. Failure to do
# so results in an error being returned from other functions.
#
# The function requires username and password as inputs.
#
# The function also allows an optional parameter, method, to be specified with
# values of either "secure" or "insecure". This controls whether or not
# subsequent API calls will use the https or http protocols. In case "secure"
# is chosen, the caller is expected to have properly registered a handler for
# the https protocol with the Tcl http package. The default is "secure".
#
# Returns a Tcl dict of the session creation response. This dict can be used
# to check for errors, warning messages, etc. See the QRZ API documentation
# for details.
#
proc ::qrz::login {username password {method secure}} {
    variable loginInfo
    variable sessionKey
    variable protocol

    if {$method == "secure"} {
        set protocol "https"
    } elseif {$method == "insecure"} {
        set protocol "http"
    } else {
        return -code error "unkown method: $method"
    }

    set sessionKey ""
    set loginInfo [list username $username password $password]
    set result [QueryApi]
    return $result
}

#
# Queries the QRZ API for a specific callsign. ::qrz::login must be called
# prior to this function.
#
# Returns a Tcl dict of the callsign lookup response. The values of this dict
# are documented in the QRZ API documentation.
#
proc ::qrz::lookupCallsign {callsign} {
    set result [QueryApi callsign $callsign]

    if {[dict exists $result QRZDatabase Session Error]} {
        error [dict get $result QRZDatabase Session Error]
    }

    return $result
}
