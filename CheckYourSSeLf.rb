#!/usr/bin/env ruby

require 'bundler/setup'
require 'aws-sdk-resources'
require 'openssl'
require 'slack-notifier'
require 'yaml'

class CheckYourSSeLf
  attr_reader :config, :slack

  def initialize
    @config = YAML.load(File.read("config.yml"))

    @slack = Slack::Notifier.new(config["slack_webhook_url"],
                                 username: config["slack_username"])
  end

  def check_yourself_before_you_wreck_yourself
    message = slack_message(imminent_disasters)

    config["slack_channels"].each do |channel|
      slack.ping(message, channel: channel, icon_emoji: config["slack_emoji"])
    end
  end

  private

  def certificate_names(iam_client)
    certificate_list = iam_client.list_server_certificates(max_items: config["aws_max_items"])
    certificate_metadata_list = certificate_list.server_certificate_metadata_list

    certificate_metadata_list.each_with_object([]) do |cert, name_list|
      name_list << cert.server_certificate_name
    end
  end

  def certificate_x509(certificate_name, iam_client)
    certificate = iam_client.get_server_certificate(server_certificate_name: certificate_name)
    certificate_body = certificate.server_certificate.certificate_body

    OpenSSL::X509::Certificate.new(certificate_body)
  end

  def common_name(certificate)
    subject = certificate.subject.to_s

    common_name_match = subject[/.+CN=(.+?)(?:\/|$)/, 1]

    if common_name_match
      common_name_match
    else
      # If the Common Name field is missing, we are dealing with a
      # Multi-Domain certificate. Return a friendly value so the
      # output makes sense.
      "Multi-Domain/SAN"
    end
  end

  def days_remaining(certificate)
    seconds_until_expiration = (certificate.not_after - Time.now).to_i
    seconds_until_expiration / 60 / 60 / 24
  end

  def expiration_output(reasons_to_panic)
    output = <<-HEADER
*The following SSL certificates are about to expire:*

```
    HEADER

    reasons_to_panic.each do |potential_crisis|
      output << <<-DETAILS
#{potential_crisis[:common_name]}
---
  Days Remaining: #{potential_crisis[:days_remaining]}
  IAM Name:       #{potential_crisis[:iam_name]}
  AWS Account:    #{potential_crisis[:account_name]}

      DETAILS
    end

    output << "```"
  end

  def expiring_certificates(account_name, iam_client)
    certificate_names(iam_client).each_with_object([]) do |certificate_name, expirations|
      certificate = certificate_x509(certificate_name, iam_client)

      timeframe = days_remaining(certificate)

      if timeframe < config["days_remaining_warning_threshold"]
        expirations << { common_name: common_name(certificate),
                         iam_name: certificate_name,
                         days_remaining: timeframe,
                         account_name: account_name }
      end
    end
  end

  def imminent_disasters
    config["aws_accounts"].each_with_object([]) do |account, utterly_doomed|
      iam_client = Aws::IAM::Client.new(region: config["aws_default_region"],
                                        access_key_id: account["aws_access_key_id"],
                                        secret_access_key: account["aws_secret_access_key"])

      expiring_account_certificates = expiring_certificates(account["name"], iam_client)

      # Add this account's expiring certificates to the overall array.
      utterly_doomed.concat(expiring_account_certificates)
    end
  end

  def slack_message(reasons_to_panic)
    if reasons_to_panic.size.zero?
      "\\o/ No certificates are expiring within the next #{config["days_remaining_warning_threshold"]} days."
    else
      expiration_output(reasons_to_panic)
    end
  end
end

chickity = CheckYourSSeLf.new
chickity.check_yourself_before_you_wreck_yourself
