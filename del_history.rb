#!ruby
# Historie Loeschen 
# Version 1.2 - 2017-05-15
# ralph.sluiters@vodafone.com
require 'date' 
require 'isps'
require 'ixlib/config'
require 'ixlib/logging'

LOGFILENAME = "del_history.log"
CONFIGFILENAME = "del_history.cfg"





SCLEVELS = {
ISPS::PlanContext::LEVEL_PLAN => "Plan",
ISPS::PlanContext::LEVEL_WISH => "Wunsch",
ISPS::PlanContext::LEVEL_ALTERNATIVE_WISH => "Ausweichwunsch",
ISPS::PlanContext::LEVEL_ABSENCE_WISH => "Abwesenheitswunsch",
ISPS::PlanContext::LEVEL_FINAL => "Aktueller Stand",
ISPS::PlanContext::LEVEL_TIME_RECORDING => "Zeiterfassung",
ISPS::PlanContext::LEVEL_ACD => "Externes System",
ISPS::PlanContext::LEVEL_AVAIL => "Verfuegbarkeit",
ISPS::PlanContext::LEVEL_ONCALL => "Rufbereitschaft",
ISPS::PlanContext::LEVEL_CORRECTION => "Korrektur",
ISPS::PlanContext::LEVEL_VERSION1 => "Backup Version 1",
ISPS::PlanContext::LEVEL_VERSION2 => "Backup Version 2",
ISPS::PlanContext::LEVEL_VERSION3 => "Backup Version 3"
}


def to_date(str)
  d,m,y = str.split(".")
  Date.new(y.to_i,m.to_i,d.to_i)
end 


Log::init(LOGFILENAME)
@cfg = Config::Cfg.new(CONFIGFILENAME)
@session = ISPS::Session.new
puts "Start"
puts "User: #{@cfg["connection"]["user"]}"

@from = to_date(@cfg["parameters"]["from"])
@to = to_date(@cfg["parameters"]["to"])
@historie_loeschen = (@cfg["parameters"]["historie_loeschen"].to_i == 1)
@plan_loeschen = (@cfg["parameters"]["plan_loeschen"].to_i == 1)
@levels = @cfg["parameters"]["levels"].split(",").map{|l| l.to_i}
@planunits = (@cfg["parameters"]["planunits"] || "").split(",").map{|pu| pu.to_i}

@sleep_time = @cfg["performance"]["sleeptime"].to_i
@ma_slice = @cfg["performance"]["ma_slice"].to_i
@ma_slice = 1 if @ma_slice < 1
@day_slice = @cfg["performance"]["day_slice"].to_i


puts "From: #{@from}"
puts "To: #{@to}"
puts "Plan loeschen: #{@plan_loeschen}"
puts "Historie loeschen: #{@historie_loeschen}"
puts "Ebenen(IDs): #{@levels.join(", ")}"
puts "Ebenen(Text): #{@levels.map{|l| SCLEVELS[l]}.join(", ")}"
puts "Planungseinheiten: #{@planunits.size==0 ? "alle" : @planunits.join(", ")}"


unless (@session.logon?("#{@cfg["connection"]["user"]}:#{@cfg["connection"]["password"]}@#{@cfg["connection"]["server"]}:#{@cfg["connection"]["port"]}"))
  puts "#{Time.now} ERROR on Login" 
end 


  def chunk_array(arr,csize)
    chunked = []
	i=0
	while (arr.size-i>csize)
	  chunked << arr.slice(i,csize)
	  i += csize
	end
	chunked << arr.slice(i,csize)
    chunked   
  end

  def chunk_date(from,to,days)
    chunked = []
	f = from
	t = from + days
	while (t<to)
	  chunked << [f,t]
	  f=t+1
	  t=f+days
	end
	chunked << [f,to]
    chunked   
  end
  
  
  def set_plancontext(from, to, levels)
    @planRep = ISPS::PlanRep.new
    @planRep.attach @session
       # Create a new planContext.
     @planContext = ISPS::PlanContext.new @planRep
     @planContext.dateFrom = from
     @planContext.dateTo = to
      
      @planContext.level = levels
      @planContext.displayLevel = ISPS::PlanContext::DISPLAY_MINIMAL
      @planContext.defLayerMode = ISPS::PlanContext::LAYER_MODE_TOP
      @planContext.planUnitIds = @PlanUnitIds
      @planContext.staffIds  = @staffIds
      @planContext.write
  end
    
	@staffRep = ISPS::StaffRep.new
    @staffRep.attach @session
    @PlanUnitIds = @planunits.size > 0 ? @planunits : @session.planUnits.map{|p| p.id}
    @staff = if @planunits.size > 0
	  s = []
	  @planunits.each do |pu|
	    s += @staffRep.planUnitMembers(pu, @from, @to)
	  end
       s.uniq
	else
	  @session.staffs
    end 
	
    @staffIds = @staff.map{|s| s.id}


	  puts "Plancontext setzen"
      set_plancontext(@from,@to,@levels)
	  puts "Starte loeschen"


      @levels.each do |level| 
        chunk_date(@from,@to,@day_slice).each do |days|
		  from, to = days 
		  puts "Zeitraum #{from} - #{to}"
		  chunk_array(@staffIds,@ma_slice).each do |staffgroup|
  		    if @plan_loeschen
  		      puts "Loesche aktuellen Plan Level #{level} fuer die MA #{staffgroup.join(",")}"
              @planContext.emptyTopLayer(level, from,to,staffgroup)     
            end
		    sleep @sleep_time if @sleep_time > 0
            if @historie_loeschen		  
  	          puts "Loesche Historie Level #{level} fuer die MA #{staffgroup.join(",")}"
		     @planContext.deleteEvolution(from,to,level,staffgroup)
		    end  
		    sleep @sleep_time if @sleep_time > 0
		  end
		end  
      end
    
      puts "Done!"

  