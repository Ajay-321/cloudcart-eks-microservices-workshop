const express=require("express"); const cors=require("cors"); const crypto=require("crypto");
const {DynamoDBClient}=require("@aws-sdk/client-dynamodb");
const {DynamoDBDocumentClient,GetCommand,PutCommand,ScanCommand}=require("@aws-sdk/lib-dynamodb");
const app=express(); app.use(cors()); app.use(express.json());
const port=process.env.PORT||3000,useDynamo=process.env.USE_DYNAMODB==="true",table=process.env.DYNAMODB_TABLE||"cloudcart-orders";
const inventoryUrl=process.env.INVENTORY_SERVICE_URL||"http://inventory-service:3000";
const paymentUrl=process.env.PAYMENT_SERVICE_URL||"http://payment-service:3000";
const db=DynamoDBDocumentClient.from(new DynamoDBClient({region:process.env.AWS_REGION}));
const memory=new Map();
app.get("/health",(_,r)=>r.json({service:"order-service",status:"ok"}));
app.get("/orders",async(_,r)=>{try{if(!useDynamo)return r.json([...memory.values()]);r.json((await db.send(new ScanCommand({TableName:table}))).Items||[])}catch(e){r.status(500).json({error:e.message})}});
app.get("/orders/:id",async(q,r)=>{try{if(!useDynamo){const x=memory.get(q.params.id);return x?r.json(x):r.status(404).json({error:"Not found"})}const x=await db.send(new GetCommand({TableName:table,Key:{orderId:q.params.id}}));x.Item?r.json(x.Item):r.status(404).json({error:"Not found"})}catch(e){r.status(500).json({error:e.message})}});
app.post("/orders",async(q,r)=>{
  const {userId,items=[]}=q.body; const orderId="ORD-"+crypto.randomUUID().slice(0,8);
  const amount=items.reduce((sum,i)=>sum+Number(i.price||0)*Number(i.quantity||1),0);
  try {
    for(const i of items){
      const rr=await fetch(inventoryUrl+"/inventory/reserve",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({productId:i.productId,quantity:i.quantity||1})});
      if(!rr.ok)return r.status(409).json({error:"Inventory reservation failed",detail:await rr.text()});
    }
    const pr=await fetch(paymentUrl+"/payments",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({orderId,amount})});
    const payment=await pr.json();
    const order={orderId,userId,items,totalAmount:amount,status:"CONFIRMED",paymentId:payment.paymentId,createdAt:new Date().toISOString()};
    if(useDynamo)await db.send(new PutCommand({TableName:table,Item:order}));else memory.set(orderId,order);
    r.status(201).json(order);
  } catch(e){r.status(500).json({error:e.message})}
});
app.listen(port,()=>console.log(`order-service listening on ${port}`));
