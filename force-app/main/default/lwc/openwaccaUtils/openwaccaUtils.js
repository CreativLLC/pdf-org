/**
 * Created by charl on 3/24/2023.
 */

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const showSuccess = (msgTitle, msgBody, self) => {
    showToast('info', 'dismissable', msgTitle, msgBody, self);
}

const showError = (msgTitle, msgBody, self) => {
    showToast('error', 'sticky', msgTitle, msgBody, self);
}

const showValidationError = (msgTitle, msgBody, self) => {
    showToast('warning', 'sticky', msgTitle, msgBody, self);
}

const showToast = (msgType, msgMode, msgTitle, msgBody, self) => {
    const evt = new ShowToastEvent({
        title: msgTitle,
        message: msgBody,
        variant: msgType,
        mode: msgMode
    });
   self.dispatchEvent(evt);
};

const logObject = (object, label) => {
    if(label){
        console.log(label + ' ::: ');
    }
    for(let key in object){
        console.log(key + ': ' + object[key]);
    }
}

const isEmpty = (object) => {
    return JSON.stringify(object) === '[]';
}

const validateEmail = (email) => {
    if(!email)
        return false;
    else
        return /^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/.test(email);
}

const validatePhone = (phone) => {
    if(!phone)
        return false;
    else if(phone.length < 7)
        return false;
    else if(/[A-Za-z]+/.test(phone))
        return false;
    else
        return true;
}

export { showSuccess };
export { showError };
export { showValidationError };
export { showToast };
export { logObject };
export { isEmpty };
export { validateEmail };
export { validatePhone };