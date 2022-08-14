import { NativeModules, NativeEventEmitter } from 'react-native';

const { WebRTCModule } = NativeModules;

const EventEmitter = {
  addListener: (string, func: (string) => any) => {}
} //new NativeEventEmitter(WebRTCModule);

export default EventEmitter;
