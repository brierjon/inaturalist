class FlagsController < ApplicationController
  before_filter :authenticate_user!, :except => [:show]
  before_filter :set_model, :except => [:update, :show, :destroy, :on]
  before_filter :model_required, :except => [:index, :update, :show, :destroy, :on]
  before_filter :load_flag, :only => [:show, :destroy, :update]
  before_filter :curator_or_owner_required, only: [ :update, :destroy ]
  
  # put the parameters for the foreign keys here
  FLAG_MODELS = [ "Observation", "Taxon", "Post", "Comment", "Identification",
    "Message", "Photo", "List", "Project", "Guide", "GuideSection", "LifeList",
    "User", "CheckList" ]
  FLAG_MODELS_ID = [ "observation_id","taxon_id","post_id", "comment_id",
    "identification_id", "message_id", "photo_id", "list_id", "project_id",
    "guide_id", "guide_section_id", "life_list_id", "user_id", "check_list_id" ]
  PARTIALS = %w(dialog)

  def index
    if request.path != "/flags" && @model && @object = @model.find_by_id(params[@param])
      # The default acts_as_flaggable index route
      @object = @object.becomes(Photo) if @object.is_a?(Photo)
      @flags = @object.flags.includes(:user, :resolver).
        paginate(page: params[:page]).
        order(id: :desc)
      @unresolved = @flags.select {|f| not f.resolved }
      @resolved = @flags.select {|f| f.resolved }
    else
      # a real index of all flags, which can be filtered by flag type
      @flag_type = params[:flag].to_s.tr("_", " ")
      @flag_types = [params[:flags]].flatten.compact
      @flag_types = ["other", Flag::INAPPROPRIATE] if @flag_types.blank?
      @resolved = if params[:resolved].blank?
        "no"
      elsif params[:resolved] == "any"
        "any"
      elsif params[:resolved].yesish?
        "yes"
      elsif params[:resolved].noish?
        "no"
      end
      @flaggable_type = params[:flaggable_type] if FLAG_MODELS.include?( params[:flaggable_type] )
      @user = User.where( login: params[:user_id] ).first || User.where( id: params[:user_id] ).first
      @user ||= User.where( login: params[:user_name] ).first
      @resolver = User.where( login: params[:resolver_id] ).first || User.where( id: params[:resolver_id] ).first
      @resolver ||= User.where( login: params[:resolver_name] ).first
      @flagger_type = params[:flagger_type] if %w(any auto user).include?( params[:flagger_type] )
      @flagger_type ||= "any"
      @taxon = Taxon.find_by_id( params[:taxon_id] )
      @flags = Flag.order( "created_at desc" )
      @flags = @flags.where( flaggable_user_id: @user.id ) if @user
      unless @flag_type.blank?
        @flags = @flags.where(flag: @flag_type)
      end
      @flags = @flags.where( flaggable_type: @flaggable_type ) unless @flaggable_type.blank?
      if @flag_types.include?( "other" )
        @flags = @flags.where( "flag NOT IN (?)", ( Flag::FLAGS - @flag_types ) )
      else
        @flags = @flags.where( "flag IN (?)", @flag_types )
      end
      if @resolved == "yes"
        @flags = @flags.where( "resolved" )
      elsif @resolved == "no"
        @flags = @flags.where( "NOT resolved" )
      end
      if @flagger_type == "auto"
        @flags = @flags.where( "flags.user_id = 0 OR flags.user_id IS NULL" )
      elsif @flagger_type == "user"
        @flagger = User.find_by_id( params[:flagger_user_id] )
        @flagger ||= User.find_by_login( params[:flagger_name] )
        if @flagger
          @flags = @flags.where( "flags.user_id = ?", @flagger )
        end
      end
      if @taxon && @flaggable_type == "Taxon"
        @flags = @flags.
          joins( "LEFT OUTER JOIN taxon_ancestors ta ON ta.taxon_id = flags.flaggable_id" ).
          where( "ta.ancestor_taxon_id = ?", @taxon )
      end
      if @resolver
        @flags = @flags.where( resolver_id: @resolver )
      end
      if @reason_query = params[:reason_query]
        @flags = @flags.where( "flag ILIKE ?", "%#{@reason_query}%" )
      end
      @flags = @flags.paginate(per_page: 50, page: params[:page])
      render :global_index, layout: "bootstrap"
    end
  end
  
  def show
    @object = @flag.flagged_object
    @object = @object.becomes(Photo) if @object.is_a?(Photo)
    user_viewed_updates_for( @flag ) if logged_in?
    respond_to do |format|
      format.html { render layout: "bootstrap" }
    end
  end
  
  def new
    @flag = Flag.new(params[:flag])
    @object = @model.find(params[@param])
    @object = @object.becomes(Photo) if @object.is_a?(Photo)
    @flag.flaggable ||= @object
    @flag.flag ||= "spam" if @object && !@object.is_a?(Taxon)
    @flags = @object.flags.where(resolved: false).includes(:user)
    if PARTIALS.include?(params[:partial])
      render :layout => false, :partial => params[:partial]
      return
    end
  end
  
  def create
    create_options = params[:flag]
    create_options[:user_id] = current_user.id
    @object = @model.find_by_id(params[:flag][:flaggable_id])
    unless @object
      flash[:error] = t(:cant_flag_an_object_that_doesnt_exist)
      redirect_to root_path
    end

    if @flag = Flag.where(create_options).where(resolved: true).first
      @flag.resolved = false
    else
      @flag = @object.flags.build(create_options)
    end
    if @flag.flag == "other" && !params[:flag_explanation].blank?
      @flag.flag = params[:flag_explanation]
    end
    if @flag.save
      flash[:notice] = t(:flag_saved_thanks_html, url: url_for( @flag ) )
    else
      flash[:error] = t(:we_had_a_problem_flagging_that_item, :flag_error => @flag.errors.full_messages.to_sentence.downcase)
    end

    if @object.is_a?(Identification) || @object.is_a?(Observation) ||
       @object.is_a?(Comment) || @object.is_a?(Photo)
      Observation.refresh_es_index
    elsif @object.is_a?(Project)
      Project.refresh_es_index
    end

    respond_to do |format|
      format.html do
        if @object.is_a?(Comment)
          redirect_to @object.parent
        elsif @object.is_a?(Identification)
          redirect_to @object.observation
        elsif @object.is_a?(Message)
          redirect_to messages_path
        elsif @object.is_a?(Photo)
          redirect_to @object.becomes(Photo)
        else
          redirect_to @object
        end
      end
      format.json do
        Observation.refresh_es_index if @object.is_a?(Observation)
        render :json => @flag.to_json
      end
    end


  end
  
  def update
    if resolver_id = params[:flag].delete("resolver_id")
      params[:flag]["resolver"] = User.find(resolver_id)
    end
    respond_to do |format|
      if @flag.update_attributes(params[:flag])
        flash[:notice] = t(:flag_saved)
      else
        flash[:notice] = t(:we_had_a_problem_flagging_that_item, :flag_error => @flag.errors.full_messages.to_sentence)
      end
      if @object.is_a?(Identification) || @object.is_a?(Observation) ||
         @object.is_a?(Comment) || @object.is_a?(Photo)
        Observation.refresh_es_index
      elsif @object.is_a?(Project)
        Project.refresh_es_index
      end
      format.html do 
        redirect_back_or_default(@flag)
      end
    end
    
  end
  
  def destroy
    @object = @flag.flaggable
    @flag.destroy
    if @object.is_a?(Identification) || @object.is_a?(Observation) ||
       @object.is_a?(Comment) || @object.is_a?(Photo)
      Observation.refresh_es_index
    elsif @object.is_a?(Project)
      Project.refresh_es_index
    end
    respond_to do |format|
      format.html { redirect_back_or_default(admin_path) }
      format.json do
        Observation.refresh_es_index if @object.is_a?(Observation)
        head :ok
      end
    end
  end

  private
  
  def load_flag
    render_404 unless @flag = Flag.where(id: params[:id] || params[:flag_id]).includes(:user, :resolver).first
  end
  
  def set_model
    params.each do |key,value|
      if FLAG_MODELS_ID.include? key
        @param = key
        object_name = key.split("_id")[0]
        @model = eval(object_name.camelcase)
        return
      end
    end
    if (@model ||= Object.const_get(params[:flag][:flaggable_type]) rescue nil)
      return
    end
  end

  def model_required
    unless @model
      flash[:notice] = t(:you_cant_flag_that)
      redirect_to observations_path
    end
  end

  def curator_or_owner_required
    unless logged_in? && @flag && (current_user.is_curator? || current_user.id == @flag.user.id)
      flash[:error] = t(:you_dont_have_permission_to_do_that)
      if session[:return_to] == request.fullpath
        redirect_to root_url
      else
        redirect_back_or_default(root_url)
      end
    end
  end
end
