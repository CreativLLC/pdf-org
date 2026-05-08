/**
 * Created by charl on 3/24/2023.
 */

public with sharing class ResourcePlannerController {
    @AuraEnabled
    public static ResourcePlannerModel getResourcePlannerModel(String filterStart, String filterEnd){
        Date filterStartDate = filterStart != null ? Date.valueOf(filterStart) : Date.today();
        Date filterEndDate = filterEnd != null ? Date.valueOf(filterEnd) : Date.today().addDays(28);
        return new ResourcePlannerModel(filterStartDate, filterEndDate);
    }

    public class ResourcePlannerModel{
        @AuraEnabled public DisplayRow datesRow {get; set;}
        @AuraEnabled public Date filterStart {get; set;}
        @AuraEnabled public Date filterEnd {get; set;}
        @AuraEnabled public List<DisplayRow> resourceDataRows {get; set;}
        @AuraEnabled public List<DisplayRow> projectDataRows {get; set;}

        public ResourcePlannerModel(Date filterStart, Date filterEnd){

            this.filterStart = filterStart;
            this.filterEnd = filterEnd;

            // Find the Monday that falls on or before the filter start
            Date firstMonday = Date.valueOf(UtilNinja.findPreviousMonday((DateTime) this.filterStart));

            // Construct the date row for the top of the table
            Date rangeStart = firstMonday;
            this.datesRow = new DisplayRow();
            this.datesRow.displayCells.add(new DisplayCell('companyProjectHeader','Resources and Projects', null ,null));
            this.datesRow.displayCells.add(new DisplayCell('resourceHoursHeader','Availability', null ,null));
            do {
                this.datesRow.displayCells.add(new DisplayCell('date' + String.valueOf(rangeStart), String.valueOf(rangeStart.format()), null, null));
                rangeStart = rangeStart.addDays(7);
            } while (rangeStart <= this.filterEnd);

            // Create data structure for the detail rows
            Map<Id, GroupModel> resourceMap = new Map<Id, GroupModel>();
            Map<Id, GroupModel> projectMap = new Map<Id, GroupModel>();

            // Prime the Projects Map with all active Projects
            for(Project__c project : [select Id, Name, Target_Weekly_Hours__c, Account__r.Name
                                        from Project__c
                                        where RecordTypeId = :projectUtils.getRecordTypeId('Active')]){
                GroupModel placeholderModel = new GroupModel();
                placeholderModel.id = project.Id;
                placeholderModel.name = '[' + project.Account__r.Name + '] ' + project.Name;
                placeholderModel.targetHours = project.Target_Weekly_Hours__c != null ? Integer.valueOf(project.Target_Weekly_Hours__c) : 0;
                projectMap.put(project.Id, placeholderModel);
            }

            List<Contact_Role__c> contactRoles = [select Id, Start_Date__c, End_Date__c,
                                                    Contact__c, Contact__r.Name, Contact__r.Max_Hours_Per_Week__c,
                                                    Project__c, Project__r.Name, Project__r.Account__r.Name, Project__r.Target_Weekly_Hours__c,
                                                    (select Id, Start_Date__c, End_Date__c, Hours__c
                                                        from Project_Allocations__r
                                                        where End_Date__c >= :filterStart
                                                        and Start_Date__c <= :filterEnd)
                                                    from Contact_Role__c
                                                    where RecordTypeId = :ContactRoleUtils.getRecordTypeId('Project_Assignment')
                                                    and Project__c in :projectMap.keySet()
                                                    and (End_Date__c = null or End_Date__c >= :filterStart)
                                                    and Start_Date__c <= :filterEnd];

            for(Contact_Role__c contactRole : contactRoles){
                GroupModel resourceModel = resourceMap.get(contactRole.Contact__c);
                if(resourceModel == null) resourceModel = new GroupModel();
                resourceModel.id = contactRole.Contact__c;
                resourceModel.name = contactRole.Contact__r.Name;
                resourceModel.targetHours = contactRole.Contact__r.Max_Hours_Per_Week__c != null ? Integer.valueOf(contactRole.Contact__r.Max_Hours_Per_Week__c) : 0;
                resourceModel.details.add(new DetailModel(contactRole));
                resourceMap.put(contactRole.Contact__c, resourceModel);

                GroupModel projectModel = projectMap.get(contactRole.Project__c);
                if(projectModel == null) projectModel = new GroupModel();
                projectModel.id = contactRole.Project__c;
                // projectModel.name = contactRole.Project__r.Name;
                projectModel.targetHours = contactRole.Project__r.Target_Weekly_Hours__c != null ? Integer.valueOf(contactRole.Project__r.Target_Weekly_Hours__c) : 0;
                projectModel.details.add(new DetailModel(contactRole));
                projectMap.put(contactRole.Project__c, projectModel);
            }

            // Construct UI model from data structure
            this.resourceDataRows = new List<DisplayRow>();
            for(String keyValue : resourceMap.keySet()){
                // Create a row for the resource with empty date cells
                GroupModel resource = resourceMap.get(keyValue);

                // Iterate through Project Allocation records for this Resource
                // and compile a total by week
                Map<Date, Integer> allocationTotalByWeek = new Map<Date, Integer>();
                for(DetailModel project : resource.details){
                    // Walk through possible allocation dates in the time range
                    rangeStart = firstMonday;
                    do {
                        AllocationModel allocation = project.allocationMap.get(rangeStart);
                        Integer currentAllocationValue = allocationTotalByWeek.get(rangeStart);
                        if(currentAllocationValue == null) currentAllocationValue = 0;
                        if(allocation != null)
                            currentAllocationValue = currentAllocationValue + allocation.allocation;
                        allocationTotalByWeek.put(rangeStart, currentAllocationValue);

                        rangeStart = rangeStart.addDays(7);
                    } while (rangeStart <= filterEnd);
                }

                // Add a row for each of the resources
                DisplayRow resourceRow = new DisplayRow();
                resourceRow.cssClass = 'mainRow';
                resourceRow.key = resource.id;
                resourceRow.displayCells.add(new DisplayCell(resource.id + 'name', resource.name, '/' + resource.id, 'leftColumn'));
                resourceRow.displayCells.add(new DisplayCell(resource.id + 'hours',String.valueOf(resource.targetHours), null ,'leftColumn'));
                rangeStart = firstMonday;
                do {
                    Integer allocationTotal = allocationTotalByWeek.get(rangeStart);
                    String cssClass = allocationTotal > resource.targetHours ? 'overAllocated' : allocationTotal < (resource.targetHours *.9) ? 'underAllocated' : 'allocated';
                    resourceRow.displayCells.add(new DisplayCell(resource.id + String.valueOf(rangeStart), String.valueOf(allocationTotal), null, cssClass));
                    rangeStart = rangeStart.addDays(7);
                } while (rangeStart <= filterEnd);
                this.resourceDataRows.add(resourceRow);

                // Add a row for each of the projects
                for(DetailModel project : resource.details){
                    DisplayRow projectRow = new DisplayRow();
                    projectRow.cssClass = 'subRow';
                    projectRow.key = project.projectId;
                    projectRow.displayCells.add(new DisplayCell(project.projectId + 'name', project.projectName, '/' + project.contactRoleId, 'leftColumn'));
                    projectRow.displayCells.add(new DisplayCell(project.projectId + 'spacer','', null ,'leftColumn'));
                    // Walk through possible allocation dates in the time range
                    rangeStart = firstMonday;
                    do {
                        AllocationModel allocation = project.allocationMap.get(rangeStart);
                        Integer allocationTotal = allocationTotalByWeek.get(rangeStart);
                        String cssClass = allocationTotal > resource.targetHours ? 'overAllocated' : allocationTotal < (resource.targetHours *.9) ? 'underAllocated' : 'allocated';
                        if(allocation != null)
                            projectRow.displayCells.add(new DisplayCell(project.projectId + allocation.id, String.valueOf(allocation.allocation), '/' + allocation.id, cssClass));
                        else
                            projectRow.displayCells.add(new DisplayCell(project.projectId + String.valueOf(rangeStart), null, null, null));

                        rangeStart = rangeStart.addDays(7);
                    } while (rangeStart <= filterEnd);
                    this.resourceDataRows.add(projectRow);
                }
            }

            this.projectDataRows = new List<DisplayRow>();
            for(String keyValue : projectMap.keySet()){
                // Create a row for the project with empty date cells
                GroupModel project = projectMap.get(keyValue);

                // Iterate through Project Allocation records for this Resource
                // and compile a total by week
                Map<Date, Integer> allocationTotalByWeek = new Map<Date, Integer>();
                for(DetailModel resource : project.details){
                    // Walk through possible allocation dates in the time range
                    rangeStart = firstMonday;
                    do {
                        AllocationModel allocation = resource.allocationMap.get(rangeStart);
                        Integer currentAllocationValue = allocationTotalByWeek.get(rangeStart);
                        if(currentAllocationValue == null) currentAllocationValue = 0;
                        if(allocation != null)
                            currentAllocationValue = currentAllocationValue + allocation.allocation;
                        allocationTotalByWeek.put(rangeStart, currentAllocationValue);

                        rangeStart = rangeStart.addDays(7);
                    } while (rangeStart <= filterEnd);
                }

                // Add a row for each of the projects
                DisplayRow projectRow = new DisplayRow();
                projectRow.cssClass = 'mainRow';
                projectRow.key = project.id;
                System.debug('project.name ' + project.name);
                projectRow.displayCells.add(new DisplayCell(project.id + 'name', project.name, '/' + project.id, 'leftColumn'));
                projectRow.displayCells.add(new DisplayCell(project.id + 'hours',String.valueOf(project.targetHours), null ,'leftColumn'));
                rangeStart = firstMonday;
                do {
                    Integer allocationTotal = allocationTotalByWeek.get(rangeStart);
                    String cssClass = allocationTotal > project.targetHours ? 'overAllocated' : allocationTotal < (project.targetHours *.9) ? 'underAllocated' : 'allocated';
                    projectRow.displayCells.add(new DisplayCell(project.id + String.valueOf(rangeStart), String.valueOf(allocationTotal), null, cssClass));
                    rangeStart = rangeStart.addDays(7);
                } while (rangeStart <= filterEnd);
                this.projectDataRows.add(projectRow);

                // Add a row for each of the resources
                for(DetailModel resource : project.details){
                    DisplayRow resourceRow = new DisplayRow();
                    resourceRow.cssClass = 'subRow';
                    resourceRow.key = resource.resourceId;
                    resourceRow.displayCells.add(new DisplayCell(resource.projectId + 'name', resource.resourceName, '/' + resource.contactRoleId, 'leftColumn'));
                    resourceRow.displayCells.add(new DisplayCell(resource.projectId + 'spacer','', null ,'leftColumn'));
                    // Walk through possible allocation dates in the time range
                    rangeStart = firstMonday;
                    do {
                        AllocationModel allocation = resource.allocationMap.get(rangeStart);
                        Integer allocationTotal = allocationTotalByWeek.get(rangeStart);
                        String cssClass = allocationTotal > project.targetHours ? 'overAllocated' : allocationTotal < (project.targetHours *.9) ? 'underAllocated' : 'allocated';
                        if(allocation != null)
                            resourceRow.displayCells.add(new DisplayCell(resource.projectId + allocation.id, String.valueOf(allocation.allocation), '/' + allocation.id, cssClass));
                        else
                            resourceRow.displayCells.add(new DisplayCell(resource.projectId + String.valueOf(rangeStart), null, null, null));

                        rangeStart = rangeStart.addDays(7);
                    } while (rangeStart <= filterEnd);
                    this.projectDataRows.add(resourceRow);
                }
            }
        }
    }

    public class GroupModel{
        @AuraEnabled public String id {get; set;}
        @AuraEnabled public String name {get; set;}
        @AuraEnabled public Integer targetHours {get; set;}
        @AuraEnabled public List<DetailModel> details {get; set;}

        public GroupModel(){
            this.details = new List<DetailModel>();
        }
    }

    public class DetailModel{
        @AuraEnabled public String resourceId {get; set;}
        @AuraEnabled public String projectId {get; set;}
        @AuraEnabled public String contactRoleId {get; set;}
        @AuraEnabled public String projectName {get; set;}
        @AuraEnabled public String resourceName {get; set;}
        @AuraEnabled public List<AllocationModel> allocations {get; set;}
        @AuraEnabled public Map<Date, AllocationModel> allocationMap {get; set;}
        public DetailModel(Contact_Role__c contactRole){
            this.contactRoleId = contactRole.Id;
            this.resourceId = contactRole.Contact__c;
            this.projectId = contactRole.Project__c;
            this.projectName = '[' + contactRole.Project__r.Account__r.Name + '] ' + contactRole.Project__r.Name;
            this.resourceName = contactRole.Contact__r.Name;
            this.allocationMap = new Map<Date, AllocationModel>();
            for(Project_Allocation__c projAllocation : contactRole.Project_Allocations__r){
                this.allocationMap.put(projAllocation.Start_Date__c, new AllocationModel(projAllocation));
            }
            this.allocations = this.allocationMap.values();
        }
    }

    public class AllocationModel{
        @AuraEnabled public String id {get; set;}
        @AuraEnabled public Integer allocation {get; set;}
        @AuraEnabled public Date startDate {get; set;}
        public AllocationModel(Project_Allocation__c projAllocation){
            this.id = projAllocation.Id;
            this.allocation = projAllocation.Hours__c != null ? Integer.valueOf(projAllocation.Hours__c) : 0;
            this.startDate = projAllocation.Start_Date__c;
        }
    }

    public class DisplayRow{
        @AuraEnabled public String key {get; set;}
        @AuraEnabled public List<DisplayCell> displayCells {get; set;}
        @AuraEnabled public String cssClass {get; set;}
        public DisplayRow(){
            displayCells = new List<DisplayCell>();
        }
        public DisplayRow(String key){
            this.key = key;
            this.displayCells = new List<DisplayCell>();
        }
    }

    public class DisplayCell{
        @AuraEnabled public String key {get; set;}
        @AuraEnabled public String label {get; set;}
        @AuraEnabled public String linkUrl {get; set;}
        @AuraEnabled public String cssClass {get; set;}

        public DisplayCell(){}
        public DisplayCell(String key, String label, String linkUrl, String cssClass){
            this.key = key;
            this.label = label;
            this.linkUrl = linkUrl;
            this.cssClass = cssClass;
        }
    }
}