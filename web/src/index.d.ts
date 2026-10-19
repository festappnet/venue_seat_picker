/** Loads the unmodified compiled Dart asset once, with shared in-flight requests. */
export declare function loadKernel(url:URL|string):Promise<void>;
export interface LayoutNode { id:string; kind:'group'|'table'|'seat'|'furniture'|'capacityArea'|'shape'|'text'; parentId?:string; transform:{x:number;y:number;rotation:number}; width:number;height:number;z?:number;locked?:boolean;label?:string;arrowHeadLength?:number;[property:string]:unknown }
export interface VenueLayoutDocument {schemaVersion:1;symbolSetVersion:1;canvas:{x:number;y:number;width:number;height:number;fill:string};nodes:LayoutNode[];sections:Record<string,unknown>[];selectionUnits:{id:string;nodeIds:string[]}[];attachments:Record<string,unknown>[];generators:Record<string,unknown>[];presets:Record<string,unknown>[];background:Record<string,unknown>|null;defaultTextStyle:Record<string,unknown>}
export interface SelectionResult {accepted:boolean;message?:string}
/** Text templates use {count}; status keys match presentation statuses. */
export type LayoutMessages = Record<'viewerLabel' | 'places' | 'place' | 'standing' | 'availableCount' | 'confirmQuantity' | 'selectedQuantity' | 'quantityRejected' | 'placeUnavailable' | 'selectedPlaces' | 'releasedPlaces' | 'selectionRejected' | 'backgroundUnavailable' | 'placesTogether' | 'pending' | 'available' | 'occupied' | 'reserved' | 'blocked' | 'unavailable' | 'disabled' | 'sold', string>;
export interface SeatPresentation {status?:string;selected?:boolean;selectable?:boolean;fill?:string;stateMarker?:'auto'|'none';label?:string;tooltip?:string;[property:string]:unknown}
export interface LayoutOptions {messages?:Partial<LayoutMessages>;document:VenueLayoutDocument;resources?:Record<string,unknown>;seatPresentation?:Record<string,SeatPresentation>;capacityPresentation?:Record<string,unknown>;onSelectionRequested?:(ids:Set<string>,selecting:boolean)=>Promise<SelectionResult>;onQuantityRequested?:(id:string,quantity:number)=>Promise<SelectionResult>;accessibilityLabel?:string;onIssues?:(issues:Record<string,unknown>[])=>void;assets?:Record<string,unknown>}
export interface LayoutHandle {update(options:Partial<LayoutOptions>):LayoutHandle;dispose():void}
export declare function mount(container:HTMLElement,options:LayoutOptions):LayoutHandle;
export declare function update(handle:LayoutHandle,options:Partial<LayoutOptions>):LayoutHandle;
export declare function dispose(handle:LayoutHandle):void;
export interface VenueLayoutKernel {readonly protocol:number;decode(json:string):string;validate(json:string):string;validateResources(resourcesJson:string):string;nearestNode(json:string,id:string,direction:"left"|"right"|"up"|"down"):string|null;compileScene(json:string,resourcesJson:string,presentationJson:string):string;compileSceneNodes(json:string,idsJson:string,resourcesJson:string,presentationJson:string):string;hitTest(json:string,x:number,y:number):string|null;interpolate(fromJson:string,toJson:string,t:number):string}
declare global {var VenueLayoutKernel:VenueLayoutKernel}

/** Verifies processed image assets before exposing immutable render data. */
export declare function loadLayoutAssets(resources:Record<string,unknown>, options?:{fetch?:typeof fetch;signal?:AbortSignal;maxBytes?:number}):Promise<Record<string,unknown>>;
