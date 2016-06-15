#!/usr/bin/env ruby

# encoding: utf-8

require 'bundler/setup'
require 'aws-sdk-resources'
require 'net/https'
require 'openssl'
require 'slack-notifier'
require 'yaml'
require 'json'

class CheckYourSSeLf
  attr_reader :config, :slack

  def initialize
    @config = YAML.load_file("config.yml")

    @slack = Slack::Notifier.new(config["slack_webhook_url"],
                                 username: config["slack_username"])
  end

  def check_yourself_before_you_wreck_yourself
    config["slack_channels"].each do |channel|
      slack_message(imminent_disasters, channel, config["slack_emoji"])
    end
  end

  private

  def all_certificates
    @all_certificates ||= (aws_certificates + remote_certificates)
  end

  def aws_certificate_names(iam_client)
    certificate_list = iam_client.list_server_certificates(max_items: config["aws_max_items"])
    certificate_metadata_list = certificate_list.server_certificate_metadata_list

    certificate_metadata_list.each_with_object([]) do |cert, name_list|
      name_list << cert.server_certificate_name
    end
  end

  def aws_certificates
    @aws_certificates ||= config["aws_accounts"].collect do |account|
      iam_client = Aws::IAM::Client.new(region: config["aws_default_region"],
                                        access_key_id: account["aws_access_key_id"],
                                        secret_access_key: account["aws_secret_access_key"])

      aws_certificate_names(iam_client).collect do |certificate_name|
        certificate = fetch_aws_certificate_x509(certificate_name, iam_client)
        {
          common_name: common_name(certificate),
          days_remaining: days_remaining(certificate),
          source: "AWS",
          extra_info: {
            iam_name: certificate_name,
            account_name: account["name"]
          }
        }
      end
    end.flatten
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

  def expiration_output(reasons_to_panic, channel, emote)
    grouped_warnings = group_warnings(reasons_to_panic)

    attachments = []
    grouped_warnings.each do |warning_level, records|
      group_records(records).each do |record|
        attachments << {
          text: format_message(record),
          color: warning_level,
          mrkdwn_in: [
            "text",
            "pretext"
          ]
        }
      end
    end

    slack.ping "*The following SSL certificates are about to expire:*", attachments: attachments,
      channel: channel, icon_emoji: emote
  end

  def fetch_aws_certificate_x509(certificate_name, iam_client)
    certificate = iam_client.get_server_certificate(server_certificate_name: certificate_name)
    certificate_body = certificate.server_certificate.certificate_body

    OpenSSL::X509::Certificate.new(certificate_body)
  end

  def group_warnings(warnings)
    warnings.group_by { |disaster|
      if disaster[:days_remaining] > config["medium_threshold"]
        'good'
      elsif disaster[:days_remaining] > config["low_threshold"]
        'warning'
      else
        'danger'
      end
    }.sort_by { |k, v|
      if k == "good"
        3
      elsif k == "warning"
        2
      else
        1
      end
    }
  end

  def group_records(records)
    records.sort {|a,b| a[:days_remaining] <=> b[:days_remaining]}
  end

  def format_message(potential_crisis)
    <<-DETAILS
*#{potential_crisis[:days_remaining]} Days* #{potential_crisis[:source]} Certificate, #{potential_crisis[:common_name]}, #{potential_crisis[:extra_info].values.flatten.join(', ')}
    DETAILS
  end

  def imminent_disasters
    all_certificates.select do |certificate|
      certificate[:days_remaining] <= config["days_remaining_warning_threshold"]
    end
  end

  def next_apocalypse
    all_certificates.sort { |a,b| a[:days_remaining] <=> b[:days_remaining] }.first
  end

  def remote_certificates
    @remote_certificates ||= config["remote_certs"].collect do |remote|
      uri = URI.parse(remote["url"])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.start do |h|
        {
          days_remaining: days_remaining(h.peer_cert),
          source: "Remote",
          common_name: remote["name"],
          extra_info: {
            url: remote["url"]
          }
        }
      end
    end.flatten
  end

  def slack_message(reasons_to_panic, channel, emote)
    if reasons_to_panic.size.zero?
      forgiving_message = <<-APOCALYPSE
\\o/ No certificates are expiring within the next #{config["days_remaining_warning_threshold"]} days.

Only #{next_apocalypse[:days_remaining]} days until the next certificate expires. /o\\
      APOCALYPSE

      slack.ping forgiving_message, channel: channel, icon_emoji: emote
    else
      expiration_output(reasons_to_panic, channel, emote)
    end
  end
end

chickity = CheckYourSSeLf.new
chickity.check_yourself_before_you_wreck_yourself
