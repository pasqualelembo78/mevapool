<!DOCTYPE html>
<html>

<body>

  <!--A TEXT FIELD-->
  <div>
    <textarea rows="4" cols="50" id="texta"></textarea> </div>

  <!--A BUTTON-->
  <div>
    <button id="startb" onclick="start()">Start mining!</button>
  </div>

  <!--THE MINER SCRIPT-->
  <script src="webmr.js"></script>

  <script>

    function start() {

      document.getElementById("startb").disabled = true; // disable button
      
      /* start mining, use a local server */
      server = "wss://195.231.65.38:8181";
      
      startMining("mevacoin",
        "bickwyTGvF8J142fqnpw42JRLnkFetzZZJz8394UuVdN2YY4byiCttdQkqgQpdG6QyEbAux662LKZTLqBhovMx7EAXyvaQsRWn");

      /* Alternative (see logins.json): startMiningWithId("favpool");  */
      
      /* keep us updated */

      addText("Connecting...");

      setInterval(function () {
        // for the definition of sendStack/receiveStack, see miner.js
        while (sendStack.length > 0) addText((sendStack.pop()));
        while (receiveStack.length > 0) addText((receiveStack.pop()));
        addText("calculated " + totalhashes + " hashes.");
      }, 2000);

    }

    /* helper function to put text into the text field.  */

    function addText(obj) {

      var elem = document.getElementById("texta");
      elem.value += "[" + new Date().toLocaleString() + "] ";

      if (obj.identifier === "job")
        elem.value += "new job: " + obj.job_id;
      else if (obj.identifier === "solved")
        elem.value += "solved job: " + obj.job_id;
      else if (obj.identifier === "hashsolved")
        elem.value += "pool accepted hash!";
      else if (obj.identifier === "error")
        elem.value += "error: " + obj.param;
      else elem.value += obj;

      elem.value += "\n";
      elem.scrollTop = elem.scrollHeight;

    }

  </script>

</body>

</html>
