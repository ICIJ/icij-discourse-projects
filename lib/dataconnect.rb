
module PostsControllerExtension
  private

  def create_params
    result = super
    if params["datashare_document_id"].present?
      result[:datashare_document_id] = params["datashare_document_id"]
    end
    result
  end
end

class ::PostsController
  prepend PostsControllerExtension
end

class ::TopicListItemSerializer
  attributes :datashare_document_id

  def datashare_document_id
    object.custom_fields["datashare_document_id"]
  end
end

module TopicCreatorExtension
  def create
    topic = super
    if @opts[:datashare_document_id]
      topic.custom_fields['datashare_document_id'] = @opts[:datashare_document_id]
      topic.save
    end
    topic
  end
end

class ::TopicCreator
  prepend TopicCreatorExtension
end


# topic = Topic.new(setup_topic_params)
# setup_tags(topic)
#
# if fields = @opts[:custom_fields]
#   topic.custom_fields.merge!(fields)
# end
#
# if @opts[:datashare_document_id]
#   topic.custom_fields['datashare_document_id'] = @opts[:datashare_document_id]
# end
#
# DiscourseEvent.trigger(:before_create_topic, topic, self)
#
# setup_auto_close_time(topic)
# process_private_message(topic)
# save_topic(topic)
# create_warning(topic)
# watch_topic(topic)
# create_shared_draft(topic)
# UserActionManager.topic_created(topic)
#
# topic
