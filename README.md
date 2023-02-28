# remailer

Client/Server Mail Networking Library for SMTP and IMAP

## Overview

This is an EventMachine Connection implementation of a high-performance
asynchronous SMTP client. Although EventMachine ships with a built-in SMTP
client, that version is limited to sending a single email per client,
and since establishing a client can be the majority of the time required
to send email, this limits throughput considerably.

## Use

The Remailer system consists of the Remailer::Connection class which works
within the EventMachine environment. To use it, create a client and then
make one or more requests to send email messages.

    EventMachine.run do
      # Establish a client to a particular SMTP server and send debugging
      # messages to STDERR.
      client = Remailer::SMTP::Client.open(
        'smtp.google.com',
        debug: STDERR
      )

      # Send a single email message through the client at the earliest
      # opportunity. Note that the client will need to be fully
      # established first and this may take upwards of ten seconds.
      client.send_email(
        'from@example.net',
        'to@example.com',
        email_content
      )

      # Send an additional message through the client. This will queue up
      # until the first has been transmitted.
      client.send_email(
        'from@example.net',
        'to@example.com',
        email_content
      )

      # Tells the client to close out when finished.
      client.close_when_complete!
    end

A Proc can be supplied as the :debug option to Remailer::Connection.open and
in this case it will be called with two parameters, type and message. An
example is given here where the information is simply dumped on STDOUT:

    client = Remailer::SMTP::Client.open(
      'smtp.google.com',
      debug: lambda { |type, message|
        puts "#{type}> #{message.inspect}"
      }
    )

The types defined include:

  * :send - Raw data sent by the client
  * :reply - Raw replies from the server
  * :options - The finalized options used to connect to the server

This callback procedure can be defined or replaced after the client is
initialized:

    client.debug do |type, message|
      STDERR.puts "%s> %s" % [ type, message.inspect ]
    end

It's also possible to define a handler for when the message queue has been
exhausted:

    client.after_complete do
      STDERR.puts "Sending complete."
    end

The call to send a message can also take a callback method which must receive
one parameter that will be the numerical status code returned by the SMTP
server. Success is defined as 250, errors vary:

    client.send_email(
      'from@example.net',
      'to@example.com',
      email_content
    ) do |status_code|
      puts "Message finished with status #{status_code}"
    end

A status code of nil is sent if the server timed out or the connection failed.

## Tests

In order to run tests, copy `test/config.example.yml` to `test/config.yml` and
adjust as required. For obvious reasons, passwords to SMTP test accounts are
not included in the source code of this library. Any Gmail-type account should
serve as a useful test target.

## Status

This software is currently experimental and is not recommended for production
use. Many of the internals may change significantly before a proper beta
release is made.

## Copyright

Copyright (c) 2010-2023 Scott Tadman, PostageApp Ltd.
