/**
 * Created by charl on 3/24/2023.
 */

import { track, LightningElement } from 'lwc';

import getResourcePlannerModel from '@salesforce/apex/ResourcePlannerController.getResourcePlannerModel';
import { showSuccess, showError, logObject } from 'c/openwaccaUtils';

export default class ResourcePlanner extends LightningElement {
    isLoading = false;
    resourceModel;
    byResourceRows;
    byProjectRows;

    connectedCallback() {
        this.init();
    }

    init() {
        this.isLoading = true;

        getResourcePlannerModel({
                filterStart: null,
                filterEnd: null
            })
            .then( result => {
                this.resourceModel = result;
                this.byResourceRows = this.resourceModel.resourceDataRows;
            })
            .catch( error => {
                this.isLoading = false;
                var pageError = 'There was an error loading page.';
                if (error && error.body && error.body.message) {
                    pageError = error.body.message;
                }
                showError('Error',  pageError, this);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleDateChange(event) {
        let elementName = event.target.dataset.name;
        console.log('elementName ' + elementName);

        let elementValue = event.target.value;
        console.log('elementValue ' + elementValue);

        if(elementName == 'startDateInput'){
            this.resourceModel.filterStart = elementValue;
        }
        else if(elementName == 'endDateInput'){
            this.resourceModel.filterEnd = elementValue;
        }
    }

    handleSearchClick(event){
        console.log('this.resourceModel.filterStart ' + this.resourceModel.filterStart);
        console.log('this.resourceModel.filterEnd ' + this.resourceModel.filterEnd);
        getResourcePlannerModel({
                filterStart: this.resourceModel.filterStart,
                filterEnd: this.resourceModel.filterEnd
            })
            .then( result => {
                this.resourceModel = result;
            })
            .catch( error => {
                this.isLoading = false;
                var pageError = 'There was an error loading page.';
                if (error && error.body && error.body.message) {
                    pageError = error.body.message;
                }
                showError('Error',  pageError, this);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    handleViewSwitch(event){
        if(this.byResourceRows){
            this.byProjectRows = this.resourceModel.projectDataRows;
            this.byResourceRows = null;
        }
        else if(this.byProjectRows){
            this.byProjectRows = null;
            this.byResourceRows = this.resourceModel.resourceDataRows;
        }
    }
}