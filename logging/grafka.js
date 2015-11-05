var net = require('net');
var HOST = '127.0.0.1';
var PORT = 2003;
var kafka = require('kafka-node');
var HighLevelProducer = kafka.HighLevelProducer;
var client = new kafka.Client('10.48.42.80:2181','metrics');
var producer = new HighLevelProducer(client);
var carrier = require('carrier');

producer.addListener('ready', function () {
  console.log('Kafka producer is ready');
});

net.createServer(function(conn) {
  console.log('CONNECTED:' + conn.remoteAddress + conn.remotePort);
    var my_carrier = carrier.carry(conn);
    my_carrier.on('line',  function(line) {
      console.log(line);
      if(producer) {
        payload = [
          { topic: 'metrics', messages: line}
        ];
        producer.send(payload, function (err, line) {
          if (err) {
            console.log('Failed to send to kafka.');
          } else {
            console.log('Message is queued');
          }
        });
      } else {
        console.log('Producer is not initialized');
      }
    });
    my_carrier.on('close', function(line) {
     console.log('CLOSED: ' + sock.remoteAddress +' '+ sock.remotePort);
  });
}).listen(PORT, HOST);
