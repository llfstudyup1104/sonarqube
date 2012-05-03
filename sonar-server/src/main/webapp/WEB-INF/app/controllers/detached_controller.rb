#
# Sonar, entreprise quality control tool.
# Copyright (C) 2008-2012 SonarSource
# mailto:contact AT sonarsource DOT com
#
# Sonar is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# Sonar is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with Sonar; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02
#
class DetachedController < ApplicationController

  SECTION=Navigation::SECTION_HOME

  verify :method => :post, :only => [:set_layout, :add_widget, :set_dashboard, :save_widget], :redirect_to => {:action => :index}
  before_filter :login_required, :except => [:index]

  def index
    # TODO display error page if no dashboard or no resource
    load_resource()
    load_dashboard()
    load_authorized_widget_definitions()
    unless @dashboard
      redirect_to home_path
    end
  end

  def configure
    # TODO display error page if no dashboard or no resource
    load_resource()
    load_dashboard()
    @category=params[:category]
    load_widget_definitions(@category)
    unless @dashboard
      redirect_to home_path
    end
  end

  def edit_layout
    load_resource()
    load_dashboard()
  end

  def set_layout
    dashboard=Dashboard.find(params[:id].to_i)
    if dashboard.editable_by?(current_user)
      dashboard.column_layout=params[:layout]
      dashboard.save!
      columns=dashboard.column_layout.split('-')
      dashboard.widgets.find(:all, :conditions => ["column_index > ?", columns.size()]).each do |widget|
        widget.column_index=columns.size()
        widget.save
      end
    end
    redirect_to :action => 'index', :did => dashboard.id, :id => params[:id]
  end

  def set_dashboard
    load_dashboard()

    dashboardstate=params[:dashboardstate]

    columns=dashboardstate.split(";")
    all_ids=[]
    columns.each_with_index do |col, index|
      ids=col.split(",")
      ids.each_with_index do |id, order|
        widget=@dashboard.widgets.to_a.find { |i| i.id==id.to_i() }
        if widget
          widget.column_index=index+1
          widget.row_index=order+1
          widget.save!
          all_ids<<widget.id
        end
      end
    end
    @dashboard.widgets.reject { |w| all_ids.include?(w.id) }.each do |w|
      w.destroy
    end
    render :json => {:status => 'ok'}
  end

  def add_widget
    dashboard=Dashboard.find(params[:id].to_i)
    widget_id=nil
    if dashboard.editable_by?(current_user)
      definition=java_facade.getWidget(params[:widget])
      if definition
        first_column_widgets=dashboard.widgets.select { |w| w.column_index==1 }.sort_by { |w| w.row_index }
        new_widget=dashboard.widgets.create(:widget_key => definition.getId(),
                                            :name => definition.getTitle(),
                                            :column_index => 1,
                                            :row_index => 1,
                                            :configured => !definition.hasRequiredProperties())
        widget_id=new_widget.id
        first_column_widgets.each_with_index do |w, index|
          w.row_index=index+2
          w.save
        end
      end
    end
    redirect_to :action => 'configure', :id => params[:id], :highlight => widget_id, :category => params[:category]
  end

  def save_widget
    widget=Widget.find(params[:wid].to_i)
    #TODO check owner of dashboard
    Widget.transaction do
      widget.properties.clear
      widget.java_definition.getWidgetProperties().each do |java_property|
        value=params[java_property.key()] || java_property.defaultValue()
        if value && !value.empty?
          prop = widget.properties.build(:kee => java_property.key, :text_value => value)
          prop.save!
        end
      end
      widget.configured=true
      widget.save!
      render :update do |page|
        page.redirect_to(url_for(:action => :configure, :id => widget.dashboard_id))
      end
    end
  end

  def widget_definitions
    @category=params[:category]
    load_widget_definitions(@category)
    render :partial => 'detached/widget_definitions', :locals => {:dashboard_id => params[:id], :category => @category}
  end

  private

  def load_dashboard
    @active=nil
    if logged_in?
      @active=ActiveDashboard.find(:first, :include => 'dashboard', :conditions => ['active_dashboards.dashboard_id=? AND active_dashboards.user_id=?', params[:id].to_i, current_user.id])
    end

    if @active.nil?
      # anonymous or not found in user dashboards
      @active=ActiveDashboard.find(:first, :include => 'dashboard', :conditions => ['active_dashboards.dashboard_id=? AND active_dashboards.user_id IS NULL', params[:id].to_i])
    end
    @dashboard=(@active ? @active.dashboard : nil)
    @dashboard_configuration=Api::DashboardConfiguration.new(@dashboard, :period_index => params[:period], :snapshot => @snapshot) if @dashboard && @snapshot
  end

  def load_resource
  end

  def load_authorized_widget_definitions
    @authorized_widget_definitions=java_facade.getWidgets().select do |widget|
      roles = widget.getUserRoles()
      roles.empty? || roles.any? { |role| (role=='user') || (role=='viewer') }
    end
  end

  def load_widget_definitions(filter_on_category=nil)
    @widget_definitions=java_facade.getWidgets().select(&:isDetached)
    @widget_categories=@widget_definitions.map(&:getWidgetCategories).flatten.uniq.sort
    unless filter_on_category.blank?
      @widget_definitions=@widget_definitions.select { |definition| definition.getWidgetCategories().to_a.include?(filter_on_category) }
    end
  end
end
