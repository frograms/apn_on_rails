# -*- encoding : utf-8 -*-
# Represents the message you wish to send. 
# An APN::Notification belongs to an APN::Device.
# 
# Example:
#   apn = APN::Notification.new
#   apn.badge = 5
#   apn.sound = 'my_sound.aiff'
#   apn.alert = 'Hello!'
#   apn.device = APN::Device.find(1)
#   apn.save
# 
# To deliver call the following method:
#   APN::Notification.send_notifications
# 
# As each APN::Notification is sent the <tt>sent_at</tt> column will be timestamped,
# so as to not be sent again.
class APN::Notification < APN::Base
  include ::ActionView::Helpers::TextHelper
  extend ::ActionView::Helpers::TextHelper
  serialize :custom_properties
  
  belongs_to :device, :class_name => 'APN::Device'
  has_one    :app,    :class_name => 'APN::App', :through => :device
  
  # Stores the text alert message you want to send to the device.
  # 
  # If the message is over 150 characters long it will get truncated
  # to 150 characters with a <tt>...</tt>
  def alert=(message)
    if !message.blank? && message.size > 150
      message = truncate(message, :length => 150)
    end
    write_attribute('alert', message)
  end
  
  # Creates a Hash that will be the payload of an APN.
  # 
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.apple_hash # => {"aps" => {"badge" => 5, "sound" => "my_sound.aiff", "alert" => "Hello!"}}
  #
  # Example 2: 
  #   apn = APN::Notification.new
  #   apn.badge = 0
  #   apn.sound = true
  #   apn.custom_properties = {"typ" => 1}
  #   apn.apple_hash # => {"aps" => {"badge" => 0, "sound" => "1.aiff"}, "typ" => "1"}
  def apple_hash
    result = {}
    result['aps'] = {}
    result['aps']['alert'] = self.alert if self.alert
    result['aps']['badge'] = self.badge.to_i if self.badge
    if self.sound
      result['aps']['sound'] = self.sound if self.sound.is_a? String
      result['aps']['sound'] = "1.aiff" if self.sound.is_a?(TrueClass)
    end
    if self.custom_properties
      self.custom_properties.each do |key,value|
        result["#{key}"] = "#{value}"
      end
    end
    result
  end
  
  # Creates the JSON string required for an APN message.
  # 
  # Example:
  #   apn = APN::Notification.new
  #   apn.badge = 5
  #   apn.sound = 'my_sound.aiff'
  #   apn.alert = 'Hello!'
  #   apn.to_apple_json # => '{"aps":{"badge":5,"sound":"my_sound.aiff","alert":"Hello!"}}'
  def to_apple_json
    self.apple_hash.to_json
  end
  
  # Creates the binary message needed to send to Apple.
  def message_for_sending
    json = self.to_apple_json
    device_token = [self.device.token.gsub(/[<\s>]/, '')].pack('H*')
    message = [0, 0, 32, device_token, 0, json.bytes.count, json].pack('ccca*cca*')

    # message가 255byte 이상일 때 alert의 길이를 잘라서 message에 다시 가공
    if message.size.to_i > 256 and self.alert
      json_obj = JSON.parse(json)
      
      # alert이 없는 상태의 길이를 구함
      json_obj['aps']['alert'] = ''
      json_without_alert = json_obj.to_json
      message_without_alert = [0, 0, 32, device_token, 0, json_without_alert.bytes.count, json_without_alert].pack('ccca*cca*')
      
      # byte 기준 최대 허용 길이를 산정하고 
      allow_size = 255 - message_without_alert.size.to_i
      # 허용된 byte 길이 만큼 자른다
      new_alert = self.alert.byteslice(0..allow_size - 1)
      # new_alert.size
      # - 1 인덱스가 0번부터
      # - 2 byteslice로 자르면 마지막 문자가 3byte로 구성된 경우(한글 등) 1byte라도 유실되면 문자가 깨지므로 마지막 문자는 아예 무시
      # - 5 말줄임표
      new_alert = "#{new_alert[0..new_alert.size - 5]}..."
      # 변경된 alert을 적용하고 message를 새로 작성하여 대체
      json_obj['aps']['alert'] = new_alert
      json_modified_alert = json_obj.to_json
      message_modified_alert = [0, 0, 32, device_token, 0, json_modified_alert.bytes.count, json_modified_alert].pack('ccca*cca*')

      message = message_modified_alert
    end
    raise APN::Errors::ExceededMessageSizeError.new(message) if message.size.to_i > 256
    message
  end
  
  def self.send_notifications
    ActiveSupport::Deprecation.warn("The method APN::Notification.send_notifications is deprecated.  Use APN::App.send_notifications instead.")
    APN::App.send_notifications
  end
  
end # APN::Notification