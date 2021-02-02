module ExtendListController
  # try creating a custom method in this controller
  def group_watching_topics
    group = Group.find_by(name: params[:group_name])
    raise Discourse::NotFound unless group
    guardian.ensure_can_see_group!(group)
    guardian.ensure_can_see_group_members!(group)

    list_opts = build_topic_list_options
    list = generate_list_for("group_watching_topics", group, list_opts)
    list.more_topics_url = construct_url_with(:next, list_opts)
    list.prev_topics_url = construct_url_with(:prev, list_opts)
    respond_with_list(list)
  end

  def watching_topics
    list_opts = build_topic_list_options
    list = generate_list_for("watching_topics", current_user, list_opts)
    list.more_topics_url = construct_url_with(:next, list_opts)
    list.prev_topics_url = construct_url_with(:prev, list_opts)
    respond_with_list(list)
  end
end

class ::ListController
  prepend ExtendListController
end
