module ExtendSearchController
  def show
    @search_term = params.permit(:q)[:q]

    # a q param has been given but it's not in the correct format
    # eg: ?q[foo]=bar
    if params[:q].present? && !@search_term.present?
      raise Discourse::InvalidParameters.new(:q)
    end

    if @search_term.present? &&
       @search_term.length < SiteSetting.min_search_term_length
      raise Discourse::InvalidParameters.new(:q)
    end

    if @search_term.present? && @search_term.include?("\u0000")
      raise Discourse::InvalidParameters.new("string contains null byte")
    end

    search_args = {
      type_filter: 'topic',
      guardian: guardian,
      include_blurbs: true,
      blurb_length: 300,
      page: if params[:page].to_i <= 10
              [params[:page].to_i, 1].max
            end
    }

    context, type = lookup_search_context
    if context
      search_args[:search_context] = context
      search_args[:type_filter] = type if type
    end

    search_args[:search_type] = :full_page
    search_args[:ip_address] = request.remote_ip
    search_args[:user_id] = current_user.id if current_user.present?

    @search_term = params[:q]
    search = Search.new(@search_term, search_args)
    result = search.execute
    result.find_user_data(guardian) if result

    serializer = serialize_data(result, GroupedSearchResultSerializer, result: result)

    respond_to do |format|
      format.html do
        store_preloaded("search", MultiJson.dump(serializer))
      end
      format.json do
        render_json_dump(serializer)
      end
    end
  end
end

class ::SearchController
  prepend ExtendSearchController
end
