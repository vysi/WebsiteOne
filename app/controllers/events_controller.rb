class EventsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_event, only: [:show, :edit, :update, :destroy, :update_only_url]
  before_action :set_projects, only: [:new, :edit, :update, :create]

  def new
    @event = Event.new(new_params)
    @event.set_repeat_ends_string
  end

  def show
    @event_schedule = @event.next_occurrences
    @recent_hangout = @event.recent_hangouts.first
    @event_instances = EventInstance.where(event_id: @event.id).where.not(yt_video_id: nil)
                                    .order(created_at: :desc).limit(5)
    render partial: 'hangouts_management' if request.xhr?
  end

  def index
    @projects = Project.active
    respond_to do |format|
      format.html { @events = Event.upcoming_events(specified_project) }
      format.json { @events = Event.upcoming_events(specified_project) }
    end
  end

  def edit
    @event.set_repeat_ends_string
  end

  def create
    params[:creator_id] = current_user.id
    EventCreatorService.new(Event).perform(transform_params,
                                                  success: -> (event) do
                                                    respond_to do |format|
                                                      format.html { redirect_to event_path(event) }
                                                      format.json { render json: {event: event} }
                                                    end
                                                  end,
                                                  failure: -> (event) do
                                                    respond_to do |format|
                                                      format.html { render :new }
                                                      format.json { render json: {error: event.errors.full_messages.to_sentence} }
                                                    end
                                                  end)
  end

  def update
    begin
      updated = @event.update_attributes(transform_params)
    rescue
      attr_error = 'attributes invalid'
    end
    if updated
      flash[:notice] = 'Event Updated'
      redirect_to event_path(@event)
    else
      flash[:alert] = ['Failed to update event:', @event.errors.full_messages, attr_error].join(' ')
      @projects = Project.all
      render 'edit'
    end
  end

  def destroy
    @event.destroy
    redirect_to events_path
  end

  private

  def transform_params
    event_params = whitelist_event_params
    create_start_date_time(event_params)
    event_params[:repeat_ends] = (event_params['repeat_ends_string'] == 'on')
    event_params[:repeat_ends_on] = params[:repeat_ends_on].present? ? "#{params[:repeat_ends_on]} UTC" : ''
    event_params[:repeats_every_n_weeks] = 2 if event_params['repeats'] == 'biweekly'
    event_params
  end

  def whitelist_event_params
    permitted = [
      :name, :category, :for, :project_id, :description, :duration, :repeats,
      :repeats_every_n_weeks, :repeat_ends_string, :time_zone, :creator_id,
      :start_datetime, :repeat_ends, :repeat_ends_on, :modifier_id, :creator_attendance,
    ]

    params.merge(event: params[:event].merge(action_initiator))
          .require(:event)
          .permit(permitted, repeats_weekly_each_days_of_the_week: [])
  end

  def action_initiator
    @event && @event.creator_id ? {modifier_id: current_user.id} : {creator_id: current_user.id}
  end

  # next_date and start_date are in the same dst or non-dst
  # next_date in dst and start_date in non-dst ==> get an hour back
  # next_date in non-dst and start_date in dst ==> ???

  def create_start_date_time(event_params)
    return unless date_and_time_present?
    tz = TZInfo::Timezone.get(params['start_time_tz'])
    event_params[:start_datetime] = next_date_offset(tz).to_utc(DateTime.parse(params['start_date'] + ' ' + params['start_time']))
  end

  def next_date_offset(tz)
    next_date_time = DateTime.parse(params['next_date'] + ' ' + params['start_time'])
    tz.period_for_utc(next_date_time).offset
  end

  def date_and_time_present?
    params['start_date'].present? and params['start_time'].present?
  end

  def specified_project
    @project = Project.friendly.find(params[:project_id]) unless params[:project_id].blank?
  end

  def set_event
    @event = Event.friendly.find(params[:id])
  end

  def set_projects
    @projects = Project.active.collect { |project| [project.title, project.id] }
  end

  def new_params
    params[:project_id] = Project.friendly.find(params[:project]).id.to_s if params[:project]
    params[:project_id] = Project.find_by(title: 'CS169').try(:id) unless params[:project_id]
    params.permit(:name, :category, :for, :project_id).merge(start_datetime: Time.now.utc, duration: 30, repeat_ends: true)
  end
end
