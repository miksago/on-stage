var path = require('path');
var net = require('net');

var EventEmitter = require('events').EventEmitter;
var LineStream = require('byline').LineStream;

var inherits = require('util').inherits

function makeCallback(maybe){
  if(typeof maybe === "function"){
    return maybe;
  }

  return function(err){
    if(err) throw err;
  }
};

function JSONParse(data, callback){
  var error = null;
  try {
    parsed = JSON.parse(data);
  }catch(e){
    error = e;
  }

  if(error){
    callback(error);
  }else {
    callback(null, parsed)
  }
}

function Client(path){
  var client = this;

  this.callbacks = [];
  this.queue = [];
  this.ready = false;

  this.socket = net.createConnection({
    path: path
  }, this._flushQueue.bind(this));

  this.socket.setEncoding('utf8');

  var parser = new LineStream();
  var buffer = [];

  parser.on('data', function(data){
    if(data !== "END"){
      buffer.push(data);
      return;
    }

    var callback = client.callbacks.shift();
    var res = buffer.splice(0, buffer.length).join("");

    if(res.substr(0, 6) === "ERROR:"){
      callback(new Error(res.slice(6)));
    } else {
      JSONParse(res, callback)
    }
  });

  this.socket.pipe(parser);
}

module.exports = Client;

Client.prototype._flushQueue = function() {
  console.log('_flushQueue');
  var data;
  while(this.queue.length && (data = this.queue.shift() )){
    this.socket.write(data);
  }

  this.ready = true;
};

Client.prototype._send = function(cmd){
  var callback = makeCallback(arguments[arguments.length - 1]);
  var cmd = Array.prototype.slice.call(arguments, 0, arguments.length - 1);

  console.log(cmd);

  this.callbacks.push(callback);

  cmd = cmd.join(" ") + "\r\n";

  console.log("<< ", cmd);

  if(this.ready){
    this.socket.write(cmd);
  } else {
    this.queue.push(cmd);
  }
};

Client.prototype.list_streams = function(callback){
  this._send("list_streams", callback);
};

Client.prototype.count = function(callback){
  this._send('count', callback);
};

Client.prototype.transition = function(to, callback){
  this._send('transition', to.toString(), callback);
};



// // 1. Connect to liquid soap over socket
// var socket = net.createConnection({
//   path: path.resolve(__dirname, "/tmp/liquidsoap-mixer")
// }, function(){
//   socket.resume();
// });

// socket.setEncoding('utf8');

// var parser = new LineStream();
// socket.pipe(parser);

// var buffer = [];

// parser.on('data', function(data){
//   if(data === "END"){
//     console.log(buffer.join(""))
//     buffer = [];
//     return;
//   }

//   buffer.push(data);
// });

// socket.write('count\r\n');
// socket.write('list_streams\r\n');
