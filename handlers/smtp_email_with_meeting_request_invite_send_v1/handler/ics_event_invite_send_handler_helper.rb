module IcsEventInviteSendHandlerHelperV1

  def parse_email(email)
    result = []
    if email.include?('<')
      # Add the address
      result << email.match(/<(.*)>/)[1]
      # Add the name
      result << email.match(/^\s*(.*?)\s*</)[1]
    else
      result << email
    end
    return result
  end

  def set_from(message, from, display_name)
    email, name = parse_email(from)
    name = display_name if !display_name.nil? && !display_name.empty?
    message.setFrom(email, name)
  end

  def add_reply_to(message, reply_to)
    message.addReplyTo(*parse_email(reply_to)) if reply_to
  end

  def add_to(message, to)
    to.each {|recipient| message.addTo(*parse_email(recipient))} if to
  end

  def add_cc(message, cc)
    cc.each {|recipient| message.addCc(*parse_email(recipient))} if cc
  end

  def add_bcc(message, bcc)
    bcc.each {|recipient| message.addBcc(*parse_email(recipient))} if bcc
  end
  
  def build_ics_attachment(content)
    # Set the file name to invite.ics
    file_name = "invite.ics"
    # Set the content type to text/calendar
    file_content_type = "application/ics"
    
    # Build the mime body part that will contain the file attachment that is to
    # be added to the email message.
    mime_body_part = javax.mail.internet.MimeBodyPart.new()
    mime_body_part.setFileName(file_name)
    mime_body_part.setHeader("Content-Type", file_content_type)
    
    # Build the data source and data handler that will populate the mime body part
    # with the attachment file contents.
    data_source = org.apache.commons.mail.ByteArrayDataSource.new(content, file_content_type)
    data_handler = javax.activation.DataHandler.new(data_source)
    mime_body_part.setDataHandler(data_handler)
    
    # IMPORTANT:  Here we set the Content-Transfer-Encoding header.  It is set here 
    # specifically because it will get overwritten if set earlier.  Also note that 
    # doing this results in the content automtically being base64 encoded.
    mime_body_part.setHeader("Content-Transfer-Encoding", "base64")

    # Return the mime_multipart object
    mime_body_part
  end

  def split_recipients(comma_separated_string)
    # Create an array of email addresses by splitting the parameter on any
    # combination of spaces followed by a comma followed by any number of spaces.
    (comma_separated_string || "").split(%r{\s*,\s*})
  end

  def unwrap_email_exception(exception)
    # Obtain the actual email_exception (which is in turn wrapped by Nativeemail_exception)
    email_exception = exception.is_a?(NativeException) ? exception.cause : exception
    # Add the real email_exception string to the stacktrace
    if email_exception.respond_to?('cause') && email_exception.cause
      # Modify the message to include the cause
      raise Exception, "#{exception.message} [#{email_exception.cause.to_s}]", exception.backtrace
      # Otherwise raise the email_exception
    else
      raise exception
    end
  end
end