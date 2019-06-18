# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class SmtpEmailWithMeetingRequestInviteSendV1
  # Include our helper
  include IcsEventInviteSendHandlerHelperV1

  # Prepare for execution by including java classes and building Hash objects
  # for necessary values, and validating the present state.  This method sets
  # the following instance variables:
  # * @input_document - A REXML::Document object that represents the input Xml.
  # * @debug_logging_enabled - A Boolean value indicating whether logging should
  #   be enabled or disabled.
  # * @server, @port, @default_displayname, @username, @password - String values
  #   retrieved from the task info records that correspond to the associated
  #   configuration value.
  # * @tls - A Boolean value indicating whether TLS encryption should be used
  #   to connecto to the SMTP server.
  # * @from, @subject, @html_body, @text_body - String values representing the
  #   values that should be used in the generated SMTP email message.
  # * @to - Array of email address Strings that represent the
  #   intended recipients
  #
  # This is a required method that is automatically called by the Kinetic Task
  # Engine.
  #
  # ==== Parameters
  # * +input+ - The String of Xml that was built by evaluating the node.xml
  #   handler template.
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Determine if debug logging is enabled
    @debug_logging_enabled = get_info_value(@input_document, 'enable_debug_logging') == 'Yes'
    puts("Logging enabled.") if @debug_logging_enabled

    # Retrieve the info values (see the get_info_value helper method below)
    @server = get_info_value(@input_document, 'server')
    @port = get_info_value(@input_document, 'port')
    @tls = get_info_value(@input_document, 'tls') == 'Yes'
    @from = get_info_value(@input_document, 'from')
    @username = get_info_value(@input_document, 'username')
    @password = get_info_value(@input_document, 'password')
    puts("Connecting to #{@server}:#{@port} #{'not ' if !@tls}using TLS as #{@username}") if @debug_logging_enabled

    # Retrieve the parameter values (see the get_parameter_value helper method below)
    @to = split_recipients(get_parameter_value(@input_document, 'to'))
    @summary = get_parameter_value(@input_document, "summary")
    @description = get_parameter_value(@input_document, "description")
    @location = get_parameter_value(@input_document, "location")
    @start_date_time = get_parameter_value(@input_document, "start_date_time")
    @end_date_time = get_parameter_value(@input_document, "end_date_time")
    
    @html_body = <<-BODY
    <div class="row" style="padding:5px;">
      <div style="float:left;font-weight:bold;width:115px;">Summary</div>
      <div style="float:left;width:500px;">#{@summary}</div>
      <div style="clear:both;"></div>
    </div>
    <div class="row" style="padding:5px;">
      <div style="float:left;font-weight:bold;width:115px;">Description</div>
      <div style="float:left;width:500px;">#{@description}</div>
      <div style="clear:both;"></div>
    </div>
    <div class="row" style="padding:5px;">
      <div style="float:left;font-weight:bold;width:115px;">Location</div>
      <div style="float:left;width:500px;">#{@location}</div>
      <div style="clear:both;"></div>
    </div>
    BODY
    
    @text_body = <<-BODY
Summary:         #{@summary}
Description:     #{@description}
Location:        #{@location}
    BODY
    
    # Raise an error if any of the required fields are blank
    raise "Required parameter 'from' is blank." if @from.nil? || @from.empty?
    raise "Required parameter 'to' is blank." if @to.length == 0
  end

  # This handler builds and sends a simple SMTP email directly to an email
  # server based on the specified info items and parameters passed to the task
  # instance.
  #
  # This is a required method that is automatically called by the Kinetic Task
  # Engine.
  #
  # ==== Returns
  # An Xml formatted String representing the return variable results.
  def execute()
    attendee_string = @to.collect {|recipient|
      "ATTENDEE:#{recipient}"
    }.join("\n")

    @calendar = <<CAL
BEGIN:VCALENDAR
CALSCALE:GREGORIAN
METHOD:REQUEST
VERSION:2.0
BEGIN:VEVENT
DTEND;VALUE=DATE-TIME:#{DateTime.parse(@end_date_time).strftime("%Y%m%dT%H%M%SZ")}
DTSTART;VALUE=DATE-TIME:#{DateTime.parse(@start_date_time).strftime("%Y%m%dT%H%M%SZ")}
#{attendee_string}
DESCRIPTION:#{@description}
SUMMARY:#{@summary}
ORGANIZER:#{@from}
UID:#{generate_guid}
LOCATION:#{@location}
END:VEVENT
END:VCALENDAR
CAL

    # Create the new email object
    message = org.apache.commons.mail.MultiPartEmail.new

    # Set the required values
    message.setHostName(@server)
    message.setSmtpPort(@port.to_i)
    message.setTLS(@tls)

    # Unless there was not a user specified
    unless @username.nil? || @username.empty?
      # Set the email authentication
      message.setAuthentication(@username, @password)
    end
    
    # Set the subject
    message.setSubject(@summary)

    # Set the email target values, these call special methods so that email
    # addresses provided with names (such as "John Doe <john.doe@domain.com>"
    # are properly parsed and configured).
    set_from(message, @from, nil)
    add_to(message, @to)

    # Build the email structure that mimics an event invite that is sent by gmail.
    multiPartAlternative = javax.mail.internet.MimeMultipart.new
    multiPartAlternative.setSubType("alternative")

    bodyPartTextPlain = javax.mail.internet.MimeBodyPart.new
    bodyPartTextPlain.setContent(@text_body, "text/plain")
    multiPartAlternative.addBodyPart(bodyPartTextPlain)

    bodyPartTextHtml = javax.mail.internet.MimeBodyPart.new
    bodyPartTextHtml.setContent(@html_body, "text/html")
    multiPartAlternative.addBodyPart(bodyPartTextHtml)

    bodyPartTextCalendar = javax.mail.internet.MimeBodyPart.new
    bodyPartTextCalendar.setContent(@calendar, "text/calendar; method=REQUEST")
    multiPartAlternative.addBodyPart(bodyPartTextCalendar)

    message.addPart(multiPartAlternative)
    message.getContainer.addBodyPart(build_ics_attachment(@calendar))

    # Send the email
    message_id = message.send();

    # Build and return the results
    results = "<results>\n  <result name='Message Id'>#{escape(message_id)}</result>\n</results>"
    puts "Results:\n#{results}" if @debug_logging_enabled
    return results
    # If we caught a EmailException error wrapper
  rescue org.apache.commons.mail.EmailException => exception
    # Unwrap and re-raise the exception.  Java and Ruby exceptions are caught and
    # handled by the Kinetic Task engine, however sometimes a handler wants to
    # add special processing for a particular exception.  In this case, the Java
    # library that we are calling creates nested exceptions (where the innermost
    # exception holds the actual error message), so it is beneficial to retrieve
    # the root exception to get to the actual error message.
    unwrap_email_exception(exception)
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(arg)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    arg.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] }
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}

  # This is a sample helper method that illustrates one method for retrieving
  # values from the input document.  As long as your node.xml document follows
  # a consistent format, these type of methods can be copied and reused between
  # handlers.
  def get_info_value(document, name)
    # Retrieve the XML node representing the desird info value
    info_element = REXML::XPath.first(document, "/handler/infos/info[@name='#{name}']")
    # If the desired element is nil, return nil; otherwise return the text value of the element
    info_element.nil? ? nil : info_element.text
  end

  # This is a sample helper method that illustrates one method for retrieving
  # values from the input document.  As long as your node.xml document follows
  # a consistent format, these type of methods can be copied and reused between
  # handlers.
  def get_parameter_value(document, name)
    # Retrieve the XML node representing the desird info value
    parameter_element = REXML::XPath.first(document, "/handler/parameters/parameter[@name='#{name}']")
    # If the desired element is nil, return nil; otherwise return the text value of the element
    parameter_element.nil? ? nil : parameter_element.text
  end

  def generate_guid
    Digest::SHA1.hexdigest("#{Process.pid.to_s}--#{Thread.current.object_id}--#{Time.now.to_f}--#{rand}")
  end
end